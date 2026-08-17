# frozen_string_literal: true

# This is a replacement for Sidekiq's built in JobLogger. Like the built in JobLogger, it
# will log job lifecycle events (start, end, failure) with timing information and job metadata.
# It will include the standard metadata for jobs:
# - Job class name
# - Job ID
# - Duration of job execution
# - Tags from the current Sidekiq context
#
# It will also include additional metadata:
# - Queue name
# - Retry count
# - Enqueued time in milliseconds (if available)
#
# Log messages will also include more information to be human readable including the job arguments:
#
#   Finished Sidekiq job MyWorker.perform("foo", 12)`
#
# You can specify at the worker level if you want to suppress arguments with the `logging => args` option:
#
#   sidekiq_options logging: {args: [:arg1]} # only `arg1` will appear in the logs
#
# Job arguments can be added as log attributes on every log entry made during the job
# by mapping `perform` parameter names to attribute names. The mapping can be set globally
# in the Sidekiq configuration or per worker; worker options take precedence:
#
#   Sidekiq.configure_server do |config|
#     config[:arg_attributes] = {user_id: "user.id"}
#   end
#
#   sidekiq_options logging: {arg_attributes: {account_id: "account.id"}}
#
# The mapped attribute names are used as given and are not prefixed with the
# `log_attribute_prefix` option.
#
# Jobs that fail are logged with the original error even when Sidekiq's retry handler
# wraps it.
#
# @example Setting up the job logger
#   Sidekiq.configure_server do |config|
#     config.logger = Lumberjack::Logger.new(STDOUT)
#     config[:job_logger] = Lumberjack::Sidekiq::JobLogger
#   end
class Lumberjack::Sidekiq::JobLogger
  # Creates a new JobLogger instance.
  #
  # @param config [Sidekiq::Config] The Sidekiq configuration object
  def initialize(config)
    @config = config
    @logger = @config.logger
    @context_logger = @logger if context_logger?(@logger)
    @prefix = @config[:log_attribute_prefix] || ""
    @message_formatter = @config[:job_logger_message_formatter] || Lumberjack::Sidekiq::MessageFormatter.new(@config)

    @global_arg_attributes = {}
    global_mapping = @config[:arg_attributes]
    global_mapping.each { |key, value| @global_arg_attributes[key.to_s] = value } if global_mapping.is_a?(Hash)
  end

  # Sidekiq server middleware hook that logs job lifecycle events (start, completion, failure)
  # with timing information and job metadata.
  #
  # @param job [Hash] The job hash containing job data
  # @param _queue [String] The queue name (unused)
  # @yield The job execution block
  # @return [void]
  def call(job, _queue)
    enqueued_time = enqueued_time_ms(job) unless skip_enqueued_time_logging?
    begin
      start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      log_start_job(job) unless skip_start_job_logging?(job)

      yield

      log_end_job(job, start, enqueued_time) unless skip_logging?(job)
    rescue Exception => err # rubocop:disable Lint/RescueException
      log_failed_job(job, unwrap_error(err), start, enqueued_time) unless skip_logging?(job)

      raise
    end
  end

  # Determines if start job logging should be skipped for the given job.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Boolean] true if start logging should be skipped
  def skip_start_job_logging?(job)
    return true if @config[:skip_start_job_logging]
    return true if skip_logging?(job)

    !!Lumberjack::Sidekiq.logging_options(job)["skip_start"]
  end

  # Determines if logging should be skipped entirely for the given job.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Boolean] true if logging should be skipped
  def skip_logging?(job)
    !!Lumberjack::Sidekiq.logging_options(job)["skip"]
  end

  # Determines if enqueued time logging should be skipped globally.
  #
  # @return [Boolean] true if enqueued time logging should be skipped
  def skip_enqueued_time_logging?
    @config[:skip_enqueued_time_logging] || false
  end

  # Prepares the logging context for a job by setting up Lumberjack attributes and
  # executing the block within that context. This includes job metadata like class name,
  # job ID, and any attributes passed through from the client.
  #
  # @param job [Hash] The job hash containing job data
  # @yield The block to execute within the logging context
  # @return [void]
  def prepare(job, &block)
    return yield unless @context_logger

    attributes = {
      "#{@prefix}class" => worker_class(job),
      "#{@prefix}jid" => job["jid"]
    }
    attributes["#{@prefix}bid"] = job["bid"] if job.include?("bid")
    attributes["#{@prefix}attributes"] = job["attributes"] if job.include?("attributes")

    persisted_attributes = passthrough_attributes(job)
    attributes.merge!(persisted_attributes) if persisted_attributes.is_a?(Hash)

    mapped_arg_attributes = arg_attributes(job)
    attributes.merge!(mapped_arg_attributes) if mapped_arg_attributes

    Lumberjack.context do
      @context_logger.tag(attributes) do
        level = Lumberjack::Sidekiq.logging_options(job)["level"] || job["log_level"]
        if level
          @context_logger.with_level(level, &block)
        else
          yield
        end
      end
    end
  end

  private

  # Logs the start of a job. Nothing is logged if the message formatter does not
  # return a message.
  #
  # @param job [Hash] The job hash containing job data
  def log_start_job(job)
    message = @message_formatter.start_job(job)
    return if message.nil?

    if @context_logger
      attributes = job_attributes(job)
      @context_logger.info(message, attributes)
    else
      @logger.info(message)
    end
  end

  # Logs the successful completion of a job. Nothing is logged if the message
  # formatter does not return a message.
  #
  # @param job [Hash] The job hash containing job data
  # @param start [Float] The start time from Process.clock_gettime
  # @param enqueued_time [Integer, nil] The enqueued time in milliseconds
  def log_end_job(job, start, enqueued_time)
    duration = elapsed_time(start)
    message = @message_formatter.end_job(job, duration)
    return if message.nil?

    if @context_logger
      attributes = job_attributes(job)
      attributes["#{@prefix}duration"] = duration
      attributes["#{@prefix}enqueued_ms"] = enqueued_time if enqueued_time
      @context_logger.info(message, attributes)
    else
      @logger.info(message)
    end
  end

  # Logs the failure of a job. Nothing is logged if the message formatter does not
  # return a message.
  #
  # @param job [Hash] The job hash containing job data
  # @param err [Exception] The exception that caused the failure
  # @param start [Float] The start time from Process.clock_gettime
  # @param enqueued_time [Integer, nil] The enqueued time in milliseconds
  def log_failed_job(job, err, start, enqueued_time)
    duration = elapsed_time(start)
    message = @message_formatter.failed_job(job, err, duration)
    return if message.nil?

    if @context_logger
      attributes = job_attributes(job)
      attributes["#{@prefix}duration"] = duration
      attributes["#{@prefix}enqueued_ms"] = enqueued_time if enqueued_time
      @context_logger.error(message, attributes)
    else
      @logger.error(message)
    end
  end

  # Calculates the elapsed time since start.
  #
  # @param start [Float] The start time from Process.clock_gettime
  # @return [Float] The elapsed time in seconds
  def elapsed_time(start)
    (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(6)
  end

  # Calculates the enqueued time in milliseconds.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Integer, nil] The enqueued time in milliseconds or nil if not available
  def enqueued_time_ms(job)
    enqueued_at = job["enqueued_at"]
    return nil unless enqueued_at.is_a?(Numeric)

    # Older versions of Sidekiq stored the time as the number of seconds in a float.
    # As of Sidekiq 8 it is stored as an integer in milliseconds.
    enqueued_at = (enqueued_at * 1000).round if enqueued_at.is_a?(Float)
    enqueued_ms = ((Time.now.to_f * 1000) - enqueued_at).round
    enqueued_ms = 0 if enqueued_ms < 0
    enqueued_ms
  end

  # Builds job attributes hash for logging.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Hash] Hash of attributes to add to the log entry
  def job_attributes(job)
    attributes = {}

    retry_count = job["retry_count"]
    attributes["#{@prefix}retry_count"] = retry_count if retry_count

    attributes["#{@prefix}queue"] = job["queue"] if job["queue"]

    ::Sidekiq::Context.current&.each do |attribute, value|
      attributes["#{@prefix}#{attribute}"] = value
    end

    attributes
  end

  # Extracts the worker class name from job data.
  #
  # @param job [Hash] The job hash containing job data
  # @return [String] The worker class name
  def worker_class(job)
    job["display_class"] || job["wrapped"] || job["class"]
  end

  # Extracts passthrough attributes from job logging configuration.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Hash, nil] The passthrough attributes or nil if none
  def passthrough_attributes(job)
    Lumberjack::Sidekiq.logging_options(job)["attributes"]
  end

  # Sidekiq's retry handler wraps job errors before re-raising them out of the
  # job execution stack. Unwrap the original error so logs show what actually failed.
  #
  # @param err [Exception] The rescued exception
  # @return [Exception] The original error if it was wrapped by the retry handler
  def unwrap_error(err)
    if defined?(::Sidekiq::JobRetry::Handled) && err.is_a?(::Sidekiq::JobRetry::Handled) && err.cause
      err.cause
    else
      err
    end
  end

  # Maps job arguments to log attributes. The mapping is defined with the global
  # `arg_attributes` Sidekiq option merged with the worker's `logging.arg_attributes`
  # option. Mapping keys are perform method parameter names and values are the
  # attribute names to set. The attribute names are used as given and are not
  # prefixed with the log attribute prefix.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Hash, nil] The mapped attributes or nil if there are none
  def arg_attributes(job)
    mapping = arg_attributes_mapping(job)
    return nil if mapping.empty?

    args = job["args"]
    return nil unless args.is_a?(Array)

    perform_args = Lumberjack::Sidekiq.perform_parameters(job)
    return nil if perform_args.nil?

    attributes = {}
    mapping.each do |arg_name, attribute_name|
      next if attribute_name.nil? || attribute_name.to_s.empty?

      index = perform_args.find_index { |param| param[1].to_s == arg_name }
      next unless index && index < args.size

      # Only positional parameters map to the job argument list. A splat parameter
      # maps to all of the remaining arguments.
      kind = perform_args[index][0]
      next unless [:req, :opt, :rest].include?(kind)

      attributes[attribute_name.to_s] = (kind == :rest) ? args[index..] : args[index]
    end
    attributes
  end

  # Builds the argument to attribute name mapping for a job. Worker level options
  # take precedence over the global configuration.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Hash] The mapping of perform parameter names to attribute names
  def arg_attributes_mapping(job)
    job_mapping = Lumberjack::Sidekiq.logging_options(job)["arg_attributes"]
    return @global_arg_attributes unless job_mapping.is_a?(Hash)

    mapping = @global_arg_attributes.dup
    job_mapping.each { |key, value| mapping[key.to_s] = value }
    mapping
  end

  # Detect if a logger is a Lumberjack logger or a wrapped Lumberjack logger
  def context_logger?(logger)
    return true if logger.is_a?(Lumberjack::ContextLogger)

    defined?(Lumberjack::Rails::BroadcastLoggerExtension) && logger.is_a?(Lumberjack::Rails::BroadcastLoggerExtension)
  end
end
