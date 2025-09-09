# frozen_string_literal: true

require "lumberjack"
require "sidekiq"

# Lumberjack Sidekiq integration module that provides enhanced logging capabilities
# for Sidekiq jobs with support for structured logging and attribute passthrough.
#
# This module provides:
# - {JobLogger} for structured job lifecycle logging with timing and metadata
# - {MessageFormatter} for customizable log message formatting
# - {AttributePassthroughMiddleware} for passing log attributes from client to server
#
# @author Brian Durand
# @version 1.0.0
module Lumberjack::Sidekiq
  VERSION = File.read(File.expand_path("../../../VERSION", __FILE__)).strip.freeze
end

require_relative "sidekiq/job_logger"
require_relative "sidekiq/message_formatter"
require_relative "sidekiq/attribute_passthrough_middleware"
