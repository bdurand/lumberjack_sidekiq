# frozen_string_literal: true

require "json"

# Sidekiq client middleware that can pass through log tags from the current Lumberjack
# logger to job logger when the job is executed on the Sidekiq server. This can be
# useful to maintain context in logs when a job is executed.
#
# @example
# Sidekiq.configure_client do |config|
#   config.client_middleware do |chain|
#     # Pass through :user_id and :request_id tags to the job logger.
#     chain.add(Lumberjack::Sidekiq::TagPassthroughMiddleware, :user_id, :request_id)
#   end
# end
class Lumberjack::Sidekiq::TagPassthroughMiddleware
  include ::Sidekiq::ClientMiddleware

  JSON_SAFE_TYPES = [String, Integer, Float, TrueClass, FalseClass].freeze

  # @param pass_through_tags [Array<String, Symbol>] Log tags to pass through to the job logger when the job is executed.
  def initialize(*pass_through_tags)
    @pass_through_tags = pass_through_tags.flatten.map(&:to_s)
  end

  def call(job_class_or_string, job, queue, redis_pool)
    return yield unless Sidekiq.logger.is_a?(Lumberjack::Logger)

    job["logging"] ||= {}
    tags = job["logging"]["tags"] || {}

    @pass_through_tags.each do |tag|
      value = json_value(Sidekiq.logger.tag_value(tag))
      tags[tag] = value unless value.nil?
    end

    job["logging"]["tags"] = tags unless tags.empty?

    yield
  end

  private

  def json_value(value)
    return nil if value.nil?
    return value if JSON_SAFE_TYPES.include?(value.class)

    begin
      JSON.parse(JSON.generate(value))
    rescue JSON::JSONError
      nil
    end
  end
end
