# frozen_string_literal: true

require "lumberjack"
require "sidekiq"

# Lumberjack Sidekiq integration module that provides enhanced logging capabilities
# for Sidekiq jobs with support for structured logging and attribute passthrough.
module Lumberjack::Sidekiq
  VERSION = File.read(File.expand_path("../../../VERSION", __FILE__)).strip.freeze

  class << self
    # Look up the perform method parameters for the job's worker class. This is used
    # to resolve job arguments by their parameter names. Jobs that wrap another job
    # class (i.e. ActiveJob) cannot be resolved because the job arguments hold the
    # serialized payload rather than the wrapped class's perform arguments. Results
    # are memoized per class name since a class's perform signature is stable. The
    # memoization is bypassed in development mode where classes can be reloaded.
    #
    # @param job [Hash] The job hash containing job data
    # @return [Array<Array>, nil] The perform method parameters or nil if the worker
    #   class cannot be resolved
    def perform_parameters(job)
      return nil if job["wrapped"]

      class_name = job["class"]
      return nil unless class_name.is_a?(String)

      # Class reloading in development mode can change a perform method signature
      # while the process runs, so cached results cannot be trusted there.
      return lookup_perform_parameters(class_name) if development_mode?

      @perform_parameters_lock.synchronize do
        cache = @perform_parameters_cache
        if cache.key?(class_name)
          cache[class_name]
        else
          cache.clear if cache.size >= 1000
          cache[class_name] = lookup_perform_parameters(class_name)
        end
      end
    end

    # Get the logging options hash for a job. Returns an empty hash if the job's
    # logging option is not a hash. The returned hash can be shared with the job
    # payload and must not be mutated.
    #
    # @param job [Hash] The job hash containing job data
    # @return [Hash] The job's logging options
    def logging_options(job)
      logging = job["logging"]
      logging.is_a?(Hash) ? logging : {}
    end

    private

    # Determine if the application is running in development mode, either from
    # the Rails environment or from the conventional environment variables.
    #
    # @return [Boolean] true if the application environment is development
    def development_mode?
      if defined?(::Rails.env)
        ::Rails.env.development?
      else
        (ENV["RAILS_ENV"] || ENV["APP_ENV"] || ENV["RACK_ENV"]) == "development"
      end
    end

    # @param class_name [String] The worker class name
    # @return [Array<Array>, nil] The perform method parameters or nil if the class
    #   name is not a resolvable class that defines perform
    def lookup_perform_parameters(class_name)
      klass = Object.const_get(class_name) if Object.const_defined?(class_name)
      return nil unless klass.is_a?(Class)
      return nil unless klass.method_defined?(:perform)

      klass.instance_method(:perform).parameters
    rescue NameError
      nil
    end
  end

  @perform_parameters_cache = {}
  @perform_parameters_lock = Mutex.new
end

require_relative "sidekiq/job_logger"
require_relative "sidekiq/message_formatter"
require_relative "sidekiq/attribute_passthrough_middleware"
