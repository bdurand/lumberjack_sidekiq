# frozen_string_literal: true

require "stringio"
require "sidekiq/job_logger"

require_relative "../lib/lumberjack_sidekiq"

RSpec.configure do |config|
  config.warnings = true
  config.order = :random
end

class MyWorker
  include Sidekiq::Worker

  def perform(arg1, arg2, arg3)
  end
end
