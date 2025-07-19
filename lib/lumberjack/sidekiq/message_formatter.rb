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
  #
  # Argument logging can be disabled globally by setting the `skip_logging_job_arguments` option in your
  # Sidekiq configuration.
  #
  # You can override this class or provide your own implementation that implements the `start_job`,
  # `end_job`, and `failed_job` methods and set it in your Sidekiq configuration:
  #
  #   Sidekiq.configure_server do |config|
  #     config.job_logger_message_formatter = MyCustomFormatter.new(config)
  #   end
  class MessageFormatter
    # @param config [::Sidekiq::Config] The Sidekiq configuration.
    def initialize(config)
      @config = config
    end

    # Formats the start job message.
    #
    # @param job [Hash] The job data.
    # @return [String] The formatted start job message.
    def start_job(job)
      "Start Sidekiq job #{job_info(job)}"
    end

    # Formats the end job message.
    #
    # @param job [Hash] The job data.
    # @param elapsed_time [Float] The elapsed time in seconds.
    # @return [String] The formatted end job message.
    def end_job(job, elapsed_time)
      "Finished Sidekiq job #{job_info(job)} in #{(elapsed_time * 1000).round(1)}ms"
    end

    # Formats the failed job message.
    #
    # @param job [Hash] The job data.
    # @param error [Exception] The exception that was raised.
    # @param elapsed_time [Float] The elapsed time in seconds.
    # @return [String] The formatted failed job message.
    def failed_job(job, error, elapsed_time)
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
    # returned as `['"foo"'', '12']`).
    #
    # Arguments can be filtered by the `logging.args` option in the worker sidekiq options.
    #
    # @param job [Hash] The job data.
    # @return [Array<String>] The formatted job arguments.
    def job_display_args(job)
      logger_options = job["logging"] || {}
      args_filter = logger_options["args"]
      args = job["args"]
      return [] if args.nil?
      return args.collect(&:inspect) if args_filter == true || args_filter.nil?

      if args_filter == false
        ["..."]
      else
        args_filter = Array(args_filter)
        filtered_args(job, args, args_filter)
      end
    end

    # Returns true of job arguments should never be logged.
    #
    # @return [Boolean] True if job arguments should not be logged.
    def skip_logging_job_arguments?
      @config[:skip_logging_job_arguments] || false
    end

    # Helper method to get the job worker class name. If the job has a `display_class` or `wrapped` key,
    # it will return that value for logging purposes.
    #     #
    # @param job [Hash] The job data.
    # @return [String] The worker class name.
    def worker_class(job)
      job["display_class"] || job["wrapped"] || job["class"]
    end

    private

    def filtered_args(job, args, args_filter)
      class_name = job["wrapped"] || job["class"]
      klass = Object.const_get(class_name) if class_name && Object.const_defined?(class_name)
      return ["..."] unless klass.is_a?(Class)
      return ["..."] unless klass.instance_methods.include?(:perform)

      perform_args = klass.instance_method(:perform).parameters
      args.each_with_index.map do |arg, index|
        arg_name = perform_args[index][1] if perform_args[index]
        if args_filter.include?(arg_name.to_s)
          arg.inspect
        else
          "-"
        end
      end
    end
  end
end
