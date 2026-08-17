# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

require "stringio"
require "sidekiq/job_logger"
require "sidekiq/job_retry"

begin
  require "simplecov"
  SimpleCov.start do
    add_filter ["/spec/"]
  end
rescue LoadError
end

Bundler.require(:default, :test)

require_relative "../lib/lumberjack_sidekiq"

Lumberjack.deprecation_mode = :raise
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

class MySplatWorker
  include Sidekiq::Worker

  def perform(arg1, *rest)
  end
end

if defined?(Lumberjack::Rails)
  ActiveSupport::BroadcastLogger.include?(Lumberjack::Rails::BroadcastLoggerExtension)
end
