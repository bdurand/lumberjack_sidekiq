# frozen_string_literal: true

require "lumberjack"
require "sidekiq"

# Lumberjack Sidekiq integration module that provides enhanced logging capabilities
# for Sidekiq jobs with support for structured logging and attribute passthrough.
module Lumberjack::Sidekiq
  # The version of the lumberjack_sidekiq gem.
  VERSION = File.read(File.expand_path("../../../VERSION", __FILE__)).strip.freeze
end

require_relative "sidekiq/job_logger"
require_relative "sidekiq/message_formatter"
require_relative "sidekiq/attribute_passthrough_middleware"
