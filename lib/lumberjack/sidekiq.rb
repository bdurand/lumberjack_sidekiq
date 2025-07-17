# frozen_string_literal: true

require "lumberjack"
require "sidekiq"

module Lumberjack::Sidekiq
end

require_relative "sidekiq/job_logger"
require_relative "sidekiq/tag_passthrough_middleware"
