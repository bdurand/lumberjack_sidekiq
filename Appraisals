appraise "sidekiq_8" do
  gem "sidekiq", "~> 8.0"
end

appraise "sidekiq_7" do
  gem "sidekiq", "~> 7.0"
end

appraise "lumberjack_2.0" do
  gem "lumberjack", "~> 2.0.0"
  remove_gem "lumberjack_rails"
end

appraise "without_rails" do
  remove_gem "lumberjack_rails"
end
