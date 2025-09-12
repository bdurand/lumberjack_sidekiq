# frozen_string_literal: true

require "stringio"
require "sidekiq/job_logger"

require_relative "../lib/lumberjack_sidekiq"

Lumberjack.deprecation_mode = "raise"
Lumberjack.raise_logger_errors = true

RSpec.configure do |config|
  config.warnings = true
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end

class MyWorker
  include Sidekiq::Worker

  def perform(arg1, arg2, arg3)
  end
end
