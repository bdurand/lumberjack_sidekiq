# frozen_string_literal: true

require "lumberjack"
require "sidekiq"

# Lumberjack Sidekiq integration module that provides enhanced logging capabilities
# for Sidekiq jobs with support for structured logging and attribute passthrough.
module Lumberjack::Sidekiq
  VERSION = File.read(File.expand_path("../../../VERSION", __FILE__)).strip.freeze

  class << self
    # Look up the perform method parameters for the job's worker class. This is used
    # to resolve job arguments by their parameter names. The lookup uses the actual
    # worker class rather than the display class.
    #
    # @param job [Hash] The job hash containing job data
    # @return [Array<Array>, nil] The perform method parameters or nil if the worker
    #   class cannot be resolved
    def perform_parameters(job)
      class_name = job["wrapped"] || job["class"]
      klass = Object.const_get(class_name) if class_name && Object.const_defined?(class_name)
      return nil unless klass.is_a?(Class)
      return nil unless klass.method_defined?(:perform)

      klass.instance_method(:perform).parameters
    end
  end
end

require_relative "sidekiq/job_logger"
require_relative "sidekiq/message_formatter"
require_relative "sidekiq/attribute_passthrough_middleware"
