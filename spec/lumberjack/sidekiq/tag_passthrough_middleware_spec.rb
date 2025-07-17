# frozen_string_literal: true

require "spec_helper"

require "sidekiq/job_logger"

RSpec.describe Lumberjack::Sidekiq::TagPassthroughMiddleware do
  let(:logger) { Lumberjack::Logger.new(StringIO.new) }
  let(:middleware) { Lumberjack::Sidekiq::TagPassthroughMiddleware.new(:user_id, :request_id) }
  let(:job) { {"args" => [1, 2, 3]} }

  before do
    allow(Sidekiq).to receive(:logger).and_return(logger)
  end

  describe "#call" do
    it "adds passthrough tags to the job logging options" do
      logger.tag(user_id: 123, request_id: "abc") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job["args"]).to eq([1, 2, 3])
          expect(job.dig("logging", "tags")).to eq("user_id" => 123, "request_id" => "abc")
        end
      end
    end

    it "does not add passthrough tags if they are not set in the logger" do
      logger.tag(user_id: 123) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "tags")).to eq("user_id" => 123)
        end
      end
    end

    it "does not add tags that are not in the passthrough list" do
      logger.tag(user_id: 123, foo: "bar") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "tags")).to eq("user_id" => 123)
        end
      end
    end

    it "converts values to JSON-safe types" do
      logger.tag(user_id: :foobar) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "tags")).to eq("user_id" => "foobar")
        end
      end
    end

    it "passes through tags set to hashes and arrays" do
      logger.tag(user_id: {id: 123}, request_id: [:abc, :def]) do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job.dig("logging", "tags")).to eq(
            "user_id" => {"id" => 123},
            "request_id" => ["abc", "def"]
          )
        end
      end
    end

    it "does not add tags if the logger is not a Lumberjack logger" do
      allow(Sidekiq).to receive(:logger).and_return(Logger.new(StringIO.new))
      logger.tag(user_id: 123, request_id: "abc") do
        middleware.call("MyWorker", job, "default", nil) do
          expect(job).to eq("args" => [1, 2, 3])
        end
      end
    end
  end
end
