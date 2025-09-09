# frozen_string_literal: true

# This is a replacement for Sidekiq's built-in JobLogger. Like the built-in JobLogger, it
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
# @example Setting up the job logger
#   Sidekiq.configure_server do |config|
#     config[:job_logger] = Lumberjack::Sidekiq::JobLogger
#   end
class Lumberjack::Sidekiq::JobLogger
  # Initializes the job logger with Sidekiq configuration.
  #
  # @param config [Sidekiq::Config] The Sidekiq configuration object
  def initialize(config)
    @config = config
    @logger = @config.logger
    @prefix = @config[:log_attribute_prefix] || ""
    @message_formatter = @config[:job_logger_message_formatter] || Lumberjack::Sidekiq::MessageFormatter.new(@config)
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
      log_failed_job(job, err, start, enqueued_time) unless skip_logging?(job)

      raise
    end
  end

  # Checks if start job logging should be skipped for a given job.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Boolean] True if start job logging should be skipped
  def skip_start_job_logging?(job)
    return true if @config[:skip_start_job_logging]
    return true if skip_logging?(job)

    logging_options = job["logging"]
    return false unless logging_options.is_a?(Hash)

    !!logging_options["skip_start"]
  end

  # Checks if all job logging should be skipped for a given job.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Boolean] True if job logging should be skipped
  def skip_logging?(job)
    logging_options = job["logging"]
    return false unless logging_options.is_a?(Hash)

    !!logging_options["skip"]
  end

  # Checks if enqueued time logging is disabled globally.
  #
  # @return [Boolean] True if enqueued time logging should be skipped
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
    return yield unless @logger.is_a?(Lumberjack::Logger)

    attributes = {
      "#{@prefix}class" => worker_class(job),
      "#{@prefix}jid" => job["jid"]
    }
    attributes["#{@prefix}bid"] = job["bid"] if job.include?("bid")
    attributes["#{@prefix}attributes"] = job["attributes"] if job.include?("attributes")

    persisted_attributes = passthrough_attributes(job)
    attributes.merge!(persisted_attributes) if persisted_attributes.is_a?(Hash)

    Lumberjack.context do
      @logger.tag(attributes) do
        level = job.dig("logging", "level") || job["log_level"]
        if level
          @logger.with_level(level, &block)
        else
          yield
        end
      end
    end
  end

  private

  # Logs the start of a job execution.
  #
  # @param job [Hash] The job hash containing job data
  # @return [void]
  def log_start_job(job)
    message = @message_formatter.start_job(job)
    if @logger.is_a?(Lumberjack::Logger)
      attributes = job_attributes(job)
      @logger.info(message, attributes)
    else
      @logger.info(message)
    end
  end

  # Logs the successful completion of a job execution.
  #
  # @param job [Hash] The job hash containing job data
  # @param start [Float] The start time from Process.clock_gettime
  # @param enqueued_time [Integer, nil] The time the job was enqueued in milliseconds
  # @return [void]
  def log_end_job(job, start, enqueued_time)
    message = @message_formatter.end_job(job, elapsed_time(start))
    if @logger.is_a?(Lumberjack::Logger)
      attributes = job_attributes(job)
      attributes["#{@prefix}duration"] = elapsed_time(start)
      attributes["#{@prefix}enqueued_ms"] = enqueued_time if enqueued_time
      @logger.info(message, attributes)
    else
      @logger.info(message)
    end
  end

  # Logs the failure of a job execution.
  #
  # @param job [Hash] The job hash containing job data
  # @param err [Exception] The exception that caused the job to fail
  # @param start [Float] The start time from Process.clock_gettime
  # @param enqueued_time [Integer, nil] The time the job was enqueued in milliseconds
  # @return [void]
  def log_failed_job(job, err, start, enqueued_time)
    message = @message_formatter.failed_job(job, err, elapsed_time(start))
    if @logger.is_a?(Lumberjack::Logger)
      attributes = job_attributes(job)
      attributes["#{@prefix}duration"] = elapsed_time(start)
      attributes["#{@prefix}enqueued_ms"] = enqueued_time if enqueued_time
      @logger.error(message, attributes)
    else
      @logger.error(message)
    end
  end

  # Calculates the elapsed time since job start.
  #
  # @param start [Float] The start time from Process.clock_gettime
  # @return [Float] The elapsed time in seconds, rounded to 6 decimal places
  def elapsed_time(start)
    (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(6)
  end

  # Calculates the time a job spent in the queue before execution.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Integer, nil] The enqueued time in milliseconds, or nil if not available
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

  # Builds a hash of job attributes for logging.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Hash] Hash of log attributes with proper prefixes
  def job_attributes(job)
    attributes = {}

    retry_count = job["retry_count"]
    attributes["#{@prefix}retry_count"] = retry_count if retry_count && retry_count > 0

    attributes["#{@prefix}queue"] = job["queue"] if job["queue"]

    ::Sidekiq::Context.current&.each do |attribute, value|
      attributes["#{@prefix}#{attribute}"] = value
    end

    attributes
  end

  # Extracts the worker class name from the job data.
  #
  # @param job [Hash] The job hash containing job data
  # @return [String] The worker class name for display purposes
  def worker_class(job)
    job["display_class"] || job["wrapped"] || job["class"]
  end

  # Extracts passthrough attributes from the job data.
  #
  # @param job [Hash] The job hash containing job data
  # @return [Hash, nil] Hash of passthrough attributes or nil if not present
  def passthrough_attributes(job)
    job.dig("logging", "attributes")
  end
end
