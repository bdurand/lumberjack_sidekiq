# frozen_string_literal: true

require "spec_helper"

require "sidekiq/job_logger"

RSpec.describe Lumberjack::Sidekiq::AttributePassthroughMiddleware do
  let(:logger) { Lumberjack::Logger.new(StringIO.new) }
  let(:middleware) { Lumberjack::Sidekiq::AttributePassthroughMiddleware.new(:user_id, :request_id) }
  let(:job) { {"args" => [1, 2, 3]} }

  before do
    allow(Sidekiq).to receive(:logger).and_return(logger)
  end

  describe "#call" do
    it "adds passthrough attributes to the job logging options" do
      logger.tag(user_id: 123, request_id: "abc") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job["args"]).to eq([1, 2, 3])
          expect(job.dig("logging", "attributes")).to eq("user_id" => 123, "request_id" => "abc")
        end
      end
    end

    it "runs the attributes through the attribute formatter first" do
      logger.attribute_formatter = Lumberjack::AttributeFormatter.build do |formatter|
        formatter.add_class(Integer) { |v| v * 2 }
      end
      logger.tag(user_id: 123, request_id: "abc") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "attributes")).to eq("user_id" => 246, "request_id" => "abc")
        end
      end
    end

    it "does not add passthrough attributes if they are not set in the logger" do
      logger.tag(user_id: 123) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "attributes")).to eq("user_id" => 123)
        end
      end
    end

    it "does not add attributes that are not in the passthrough list" do
      logger.tag(user_id: 123, foo: "bar") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "attributes")).to eq("user_id" => 123)
        end
      end
    end

    it "converts values to JSON-safe types" do
      logger.tag(user_id: :foobar) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "attributes")).to eq("user_id" => "foobar")
        end
      end
    end

    it "passes through attributes set to hashes and arrays" do
      logger.tag(user_id: {id: 123}, request_id: [:abc, :def]) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "attributes")).to eq(
            "user_id" => {"id" => 123},
            "request_id" => ["abc", "def"]
          )
        end
      end
    end

    it "does not mutate a shared logging options hash" do
      shared_logging = {"args" => ["arg1"], "attributes" => {"env" => "test"}}.freeze
      shared_logging["attributes"].freeze
      job["logging"] = shared_logging

      logger.tag(user_id: 123) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "attributes")).to eq("env" => "test", "user_id" => 123)
          expect(job["logging"]).not_to equal(shared_logging)
        end
      end

      other_job = {"args" => [], "logging" => shared_logging}
      logger.tag(request_id: "abc") do
        middleware.call("MyWorker", other_job, "default", nil) do
          expect(other_job.dig("logging", "attributes")).to eq("env" => "test", "request_id" => "abc")
        end
      end
    end

    it "does not add logging options to the job if there are no attributes to pass through" do
      middleware.call("MyWorker", job, "default", nil) do
        expect(job).to eq("args" => [1, 2, 3])
      end
    end

    it "does not add attributes if the logger is not a Lumberjack logger" do
      allow(Sidekiq).to receive(:logger).and_return(Logger.new(StringIO.new))
      logger.tag(user_id: 123, request_id: "abc") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job).to eq("args" => [1, 2, 3])
        end
      end
    end
  end
end
