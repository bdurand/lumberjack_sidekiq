# frozen_string_literal: true

module Lumberjack::Sidekiq
  # This class formats log messages for Sidekiq jobs. Out of the box it will log messages like these:
  #
  # - Start Sidekiq job MyWorker.perform("foo", 12)
  # - Finished Sidekiq job MyWorker.perform("foo", 12) in 123.4ms
  # - Failed Sidekiq job MyWorker.perform("foo", 12) due to RuntimeError in 123.4ms
  #
  # You can control the arguments that are logged by setting the `logging.args` option in your worker:
  #
  #   sidekiq_options logging: {args: [:arg1]} # only `arg1` will appear in the logs
  #   sidekiq_options logging: {args: false} # no arguments will appear in the logs
  #   sidekiq_options logging: {hide_args: [:arg2]} # all arguments except `arg2` will appear in the logs
  #
  # The `hide_args` option is a deny-list; entries can be `perform` parameter names or zero
  # based argument positions. The `args` allow-list takes precedence when both are set.
  #
  # Argument logging can be disabled globally by setting the `skip_logging_job_arguments` option in your
  # Sidekiq configuration.
  #
  # Argument values longer than `MAX_ARG_LENGTH` characters are truncated with an ellipsis so that
  # large values cannot overwhelm the logs.
  #
  # You can override the messages themselves by setting the `job_logger_messages` option in your
  # Sidekiq configuration with lambdas for the `start`, `end`, and `failed` messages:
  #
  #   Sidekiq.configure_server do |config|
  #     config[:job_logger_messages] = {
  #       start: ->(job) { "Running #{job_info(job)}" },
  #       end: ->(job, elapsed_time) { "Completed #{job_info(job)} in #{(elapsed_time * 1000).round(1)}ms" },
  #       failed: ->(job, error, elapsed_time) { "#{worker_class(job)} raised #{error.class.name}: #{error.message}" }
  #     }
  #   end
  #
  # The lambdas are passed the same arguments as the method they override and are evaluated in the
  # context of the message formatter, so helper methods like `job_info`, `worker_class`, and
  # `job_display_args` are available to them. Any messages you don't specify will use the default
  # format. Lambdas that don't need the trailing arguments can declare fewer parameters:
  #
  #   config[:job_logger_messages] = {end: ->(job) { "Completed #{job_info(job)}" }}
  #
  # A lambda that returns nil suppresses the log entry so messages can be omitted per job:
  #
  #   config[:job_logger_messages] = {start: ->(job) { "Running #{job_info(job)}" unless job["queue"] == "low" }}
  #
  # For full control over message formatting, you can override this class or provide your own
  # implementation that implements the `start_job`, `end_job`, and `failed_job` methods and set
  # it in your Sidekiq configuration:
  #
  #   Sidekiq.configure_server do |config|
  #     config[:job_logger_message_formatter] = MyCustomFormatter.new(config)
  #   end
  class MessageFormatter
    # Maximum number of characters of an argument value that will appear in a log message.
    MAX_ARG_LENGTH = 60

    # Marker appended to argument values that were too long to log in full.
    TRUNCATION_INDICATOR = "…"

    # @param config [::Sidekiq::Config] The Sidekiq configuration.
    def initialize(config)
      @config = config
      @start_message = message_lambda(:start)
      @end_message = message_lambda(:end)
      @failed_message = message_lambda(:failed)
    end

    # Formats the start job message.
    #
    # @param job [Hash] The job data.
    # @return [String] The formatted start job message.
    def start_job(job)
      return call_message(@start_message, [job]) if @start_message

      "Start Sidekiq job #{job_info(job)}"
    end

    # Formats the end job message.
    #
    # @param job [Hash] The job data.
    # @param elapsed_time [Float] The elapsed time in seconds.
    # @return [String] The formatted end job message.
    def end_job(job, elapsed_time)
      return call_message(@end_message, [job, elapsed_time]) if @end_message

      "Finished Sidekiq job #{job_info(job)} in #{(elapsed_time * 1000).round(1)}ms"
    end

    # Formats the failed job message.
    #
    # @param job [Hash] The job data.
    # @param error [Exception] The exception that was raised.
    # @param elapsed_time [Float] The elapsed time in seconds.
    # @return [String] The formatted failed job message.
    def failed_job(job, error, elapsed_time)
      return call_message(@failed_message, [job, error, elapsed_time]) if @failed_message

      "Failed Sidekiq job #{job_info(job)} due to #{error.class.name} in #{(elapsed_time * 1000).round(1)}ms"
    end

    # Helper method to get the method called on the job worker and format the arguments.
    #
    # @param job [Hash] The job data.
    # @return [String] The formatted job information.
    # @note If `skip_logging_job_arguments?` is true, it will only return the worker class name.
    def job_info(job)
      return worker_class(job) if skip_logging_job_arguments?

      display_args = job_display_args(job)
      "#{worker_class(job)}.perform(#{display_args.join(", ")})"
    end

    # Helper method to get the job arguments for logging. The return value is an array
    # of strings representing the inspect of each argument (i.e. `["foo", 12]` will be
    # returned as `['"foo"'', '12']`). Values longer than `MAX_ARG_LENGTH` characters are
    # truncated so that large arguments cannot overwhelm the logs.
    #
    # Arguments can be filtered by the `logging.args` option in the worker sidekiq options.
    #
    # @param job [Hash] The job data.
    # @return [Array<String>] The formatted job arguments.
    def job_display_args(job)
      logger_options = Lumberjack::Sidekiq.logging_options(job)
      args_filter = logger_options["args"]
      hide_filter = logger_options["hide_args"] if args_filter.nil? || args_filter == true
      args = job["args"]
      return [] if args.nil?

      if args_filter == false
        ["..."]
      elsif !args_filter.nil? && args_filter != true
        filtered_args(job, args, Array(args_filter))
      elsif hide_filter
        hidden_args(job, args, Array(hide_filter))
      else
        args.collect { |arg| display_arg(arg) }
      end
    end

    # Returns true if job arguments should never be logged.
    #
    # @return [Boolean] True if job arguments should not be logged.
    def skip_logging_job_arguments?
      @config[:skip_logging_job_arguments] || false
    end

    # Helper method to get the job worker class name. If the job has a `display_class` or `wrapped` key,
    # it will return that value for logging purposes.
    #
    # @param job [Hash] The job data.
    # @return [String] The worker class name.
    def worker_class(job)
      job["display_class"] || job["wrapped"] || job["class"]
    end

    private

    # Looks up a message lambda from the `job_logger_messages` configuration option.
    #
    # @param name [Symbol] The message name (:start, :end, or :failed).
    # @return [#call, nil] The lambda or nil if it was not configured.
    # @raise [ArgumentError] If the configured value cannot be called.
    def message_lambda(name)
      messages = @config[:job_logger_messages]
      return nil unless messages.is_a?(Hash)

      callable = messages[name] || messages[name.to_s]
      return nil if callable.nil?
      unless callable.respond_to?(:call)
        raise ArgumentError, "Sidekiq job_logger_messages[#{name.inspect}] must respond to `call`"
      end

      callable
    end

    # Calls a message lambda in the context of this formatter so that it can use the helper methods.
    # Callables that declare fewer parameters than are available are only passed the ones they accept.
    #
    # @param callable [#call] The configured message lambda.
    # @param args [Array] The arguments available to the lambda.
    # @return [String] The formatted message.
    def call_message(callable, args)
      if callable.is_a?(Proc)
        arity = callable.arity
        args = args.first(arity) if arity >= 0
        instance_exec(*args, &callable)
      else
        arity = callable.method(:call).arity
        args = args.first(arity) if arity >= 0
        callable.call(*args)
      end
    end

    # Filters job arguments based on the args filter configuration.
    #
    # @param job [Hash] The job data
    # @param args [Array] The job arguments
    # @param args_filter [Array] The list of argument names to include
    # @return [Array<String>] The filtered arguments for display
    def filtered_args(job, args, args_filter)
      perform_args = Lumberjack::Sidekiq.perform_parameters(job)
      return ["..."] if perform_args.nil?

      args_filter = args_filter.map(&:to_s)
      args.each_with_index.map do |arg, index|
        arg_name = perform_args[index][1] if perform_args[index]
        if args_filter.include?(arg_name.to_s)
          display_arg(arg)
        else
          "-"
        end
      end
    end

    # Hides job arguments named in the deny-list filter. The filter can contain
    # perform method parameter names or zero based argument positions.
    #
    # @param job [Hash] The job data
    # @param args [Array] The job arguments
    # @param hide_filter [Array] The list of argument names or positions to hide
    # @return [Array<String>] The filtered arguments for display
    def hidden_args(job, args, hide_filter)
      positions, names = hide_filter.partition { |key| key.is_a?(Integer) }
      names = names.map(&:to_s)

      unless names.empty?
        perform_args = Lumberjack::Sidekiq.perform_parameters(job)
        return ["..."] if perform_args.nil?

        perform_args.each_with_index do |(kind, name), index|
          next unless names.include?(name.to_s)

          # A splat parameter covers all of the remaining arguments.
          if kind == :rest
            positions.concat((index...args.size).to_a)
          else
            positions << index
          end
        end
      end

      args.each_with_index.map do |arg, index|
        positions.include?(index) ? "-" : display_arg(arg)
      end
    end

    # Renders a single argument value for a log message. Values longer than
    # MAX_ARG_LENGTH characters are truncated and marked with an ellipsis so that
    # large arguments cannot overwhelm the logs.
    #
    # @param arg [Object] The job argument
    # @return [String] The argument value for display
    def display_arg(arg)
      return truncate(arg.inspect) unless arg.is_a?(String)
      return arg.inspect if arg.length <= MAX_ARG_LENGTH

      # Strings are truncated before they are inspected so the quotes stay balanced.
      # The indicator is added after inspecting so that it is never escaped.
      "#{arg[0, MAX_ARG_LENGTH - 1].inspect.delete_suffix('"')}#{TRUNCATION_INDICATOR}\""
    end

    # Truncates a value to MAX_ARG_LENGTH characters, replacing the last character
    # with the truncation indicator.
    #
    # @param value [String] The value to truncate
    # @return [String] The value, no longer than MAX_ARG_LENGTH characters
    def truncate(value)
      return value if value.length <= MAX_ARG_LENGTH

      "#{value[0, MAX_ARG_LENGTH - 1]}#{TRUNCATION_INDICATOR}"
    end
  end
end
