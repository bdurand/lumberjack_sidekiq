# frozen_string_literal: true

# This is a replacement for Sidekiq's built in JobLogger. Like the built in JobLogger, it
# will log job lifecycle events (start, end, failure) with timing information and job metadata.
# It the standard metadata for jobs:
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
# Log messages will also include more information to be human readable include the jog arguments:
#
#   Finished Sidekiq job MyWorker.perform("foo", 12)`
#
# You can specify at the worker level if you want to suppress arguments with the `logging => args` option:
#
#   sidekiq_options logging: {args: [:arg1]} # only `arg1` will appear in the logs
#
# @example
# Sidekiq.configure_server do |config|
#   config.logger = Lumberjack::Sidekiq::JobLogger.new(config)
# end
class Lumberjack::Sidekiq::JobLogger
  def initialize(config)
    @config = config
    @logger = @config.logger
    @prefix = @config[:log_tag_prefix] || ""
  end

  def call(job, _queue)
    enqueued_time = enqueued_time_ms(job) unless skip_enqueued_time_logging?
    begin
      start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      log_start_job(job) unless skip_start_job_logging?(job)

      yield

      log_end_job(job, start, enqueued_time) unless skip_logging?(job)
    rescue Exception => err
      log_failed_job(job, err, start, enqueued_time) unless skip_logging?(job)

      raise
    end
  end

  # If true don't log the start of the job.
  def skip_start_job_logging?(job)
    return true if @config[:skip_start_job_logging]
    return true if skip_logging?(job)

    logging_options = job["logging"]
    return false unless logging_options.is_a?(Hash)

    !!logging_options["skip_start"]
  end

  def skip_logging?(job)
    logging_options = job["logging"]
    return false unless logging_options.is_a?(Hash)

    !!logging_options["skip"]
  end

  def skip_enqueued_time_logging?
    @config[:skip_enqueued_time_logging] || false
  end

  def skip_logging_arguments?(job)
    @config[:skip_logging_arguments] || false
  end

  def prepare(job, &block)
    return yield unless @logger.is_a?(Lumberjack::Logger)

    tags = {
      "#{@prefix}class" => worker_class(job),
      "#{@prefix}jid" => job["jid"]
    }
    tags["#{@prefix}bid"] = job["bid"] if job.include?("bid")
    tags["#{@prefix}tags"] = job["tags"] if job.include?("tags")

    persisted_tags = passthrough_tags(job)
    tags.merge!(persisted_tags) if persisted_tags.is_a?(Hash)

    @logger.tag(tags) do
      level = job.dig("logging", "level") || job["log_level"]
      if level
        @logger.silence(level, &block)
      else
        yield
      end
    end
  end

  private

  def log_start_job(job)
    message = "Start Sidekiq job #{job_info(job)}"
    if @logger.is_a?(Lumberjack::Logger)
      tags = job_tags(job)
     @logger.info(message, tags)
    else
      @logger.info(message)
    end
  end

  def log_end_job(job, start, enqueued_time)
    message = "Finished Sidekiq job #{job_info(job)}"
    if @logger.is_a?(Lumberjack::Logger)
      tags = job_tags(job)
      tags["#{@prefix}duration"] = elapsed_time(start)
      tags["#{@prefix}enqueued_ms"] = enqueued_time if enqueued_time
      @logger.info(message, tags)
    else
      @logger.info(message)
    end
  end

  def log_failed_job(job, err, start, enqueued_time)
    message = "Failed Sidekiq job #{job_info(job)}"
    if @logger.is_a?(Lumberjack::Logger)
      tags = job_tags(job)
      tags["#{@prefix}duration"] = elapsed_time(start)
      tags["#{@prefix}enqueued_ms"] = enqueued_time if enqueued_time
      @logger.error(message, tags)
    else
      @logger.error(message)
    end
  end

  def elapsed_time(start)
    (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(6)
  end

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

  def job_info(job)
    return worker_class(job) if skip_logging_arguments?(job)

    logger_options = job["logging"] || {}
    args_filter = logger_options["args"]
    args = job["args"]
    display_args = if args_filter == true || args_filter.nil?
      args
    elsif args_filter.is_a?(Array)
      filtered_args(job, args, args_filter)
    else
      ["..."]
    end

    "#{worker_class(job)}.perform(#{display_args.join(", ")})"
  end

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

  def job_tags(job)
    tags = {}

    retry_count = job["retry_count"]
    tags["#{@prefix}retry_count"] = retry_count if retry_count && retry_count > 0

    tags["#{@prefix}queue"] = job["queue"] if job["queue"]

    ::Sidekiq::Context.current&.each do |tag, value|
      tags["#{@prefix}#{tag}"] = value
    end

    tags
  end

  def worker_class(job)
    job["display_class"] || job["wrapped"] || job["class"]
  end

  def passthrough_tags(job)
    job.dig("logging", "tags")
  end
end
