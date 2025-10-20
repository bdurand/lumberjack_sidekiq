# frozen_string_literal: true

require "json"

# Sidekiq client middleware that can pass through log attributes from the current Lumberjack
# logger to job logger when the job is executed on the Sidekiq server. This can be
# useful to maintain context in logs when a job is executed.
#
# @example Adding middleware to pass through attributes
#   Sidekiq.configure_client do |config|
#     config.client_middleware do |chain|
#       # Pass through :user_id and :request_id attributes to the job logger.
#       chain.add(Lumberjack::Sidekiq::AttributePassthroughMiddleware, :user_id, :request_id)
#     end
#   end
class Lumberjack::Sidekiq::AttributePassthroughMiddleware
  include ::Sidekiq::ClientMiddleware

  # Types that can be safely serialized to JSON without losing information
  JSON_SAFE_TYPES = [String, Integer, Float, TrueClass, FalseClass].freeze

  # @param pass_through_attributes [Array<String, Symbol>] Log attributes to pass through to the job logger when the job is executed.
  def initialize(*pass_through_attributes)
    @pass_through_attributes = pass_through_attributes.flatten.map(&:to_s)
  end

  # Sidekiq client middleware hook that adds configured log attributes to the job data
  # so they can be used by the job logger when the job is executed.
  #
  # @param job_class_or_string [String, Class] The worker class or class name
  # @param job [Hash] The job hash containing job data
  # @param queue [String] The queue name
  # @param redis_pool [ConnectionPool] The Redis connection pool
  # @yield The next middleware in the chain
  # @return [void]
  def call(job_class_or_string, job, queue, redis_pool)
    return yield unless Sidekiq.logger.is_a?(Lumberjack::Logger)

    job["logging"] ||= {}
    attributes = job["logging"]["attributes"] || {}

    unless @pass_through_attributes.empty?
      logger_attributes = logger_attributes_helper
      @pass_through_attributes.each do |attribute|
        value = json_value(logger_attributes[attribute])
        attributes[attribute] = value unless value.nil?
      end
    end

    job["logging"]["attributes"] = attributes unless attributes.empty?

    yield
  end

  private

  # Gets logger attributes helper for extracting formatted attributes.
  #
  # @return [Lumberjack::AttributesHelper] Helper for accessing formatted attributes
  def logger_attributes_helper
    attributes = Sidekiq.logger.attributes
    formatter = Sidekiq.logger.attribute_formatter
    if formatter
      attributes = formatter.format(attributes)
    end
    Lumberjack::AttributesHelper.new(attributes)
  end

  # Converts a value to a JSON-safe format.
  #
  # @param value [Object] The value to convert
  # @return [Object, nil] JSON-safe value or nil if conversion fails
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
