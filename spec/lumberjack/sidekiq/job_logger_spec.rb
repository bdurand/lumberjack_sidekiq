# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::Sidekiq::JobLogger do
  let(:logger) { Lumberjack::Logger.new(out) }
  let(:config) { Sidekiq::Config.new.tap { |c| c.logger = logger } }
  let(:job_logger) { Lumberjack::Sidekiq::JobLogger.new(config) }
  let(:job) { {"class" => "MyWorker", "args" => [1, 2, 3], "jid" => "12345"} }
  let(:out) { StringIO.new }

  describe "#prepare" do
    it "has the same signature as the Sidekiq::JobLogger#prepare method" do
      job_logger = Sidekiq::JobLogger.new(config)
      value = nil
      job_logger.prepare(job) do
        value = "foobar"
      end
      expect(value).to eq("foobar")
    end

    context "when logger is not a Lumberjack logger" do
      let(:logger) { Logger.new(out) }

      it "does not error if the logger is not a Lumberjack logger" do
        allow(Sidekiq).to receive(:logger).and_return(Logger.new(StringIO.new))
        value = nil
        job_logger.prepare(job) do
          value = "foobar"
        end
        expect(value).to eq("foobar")
      end
    end

    it "adds tags with the jid and class of the job" do
      job_logger.prepare(job) do
        expect(logger.tag_value("jid")).to eq("12345")
        expect(logger.tag_value("class")).to eq("MyWorker")
      end
    end

    it "adds tags with the bid if present" do
      job["bid"] = "67890"
      job_logger.prepare(job) do
        expect(logger.tag_value("bid")).to eq("67890")
      end
    end

    it "adds tags with the job's custom tags" do
      job["tags"] = ["tag1", "tag2"]
      job_logger.prepare(job) do
        expect(logger.tag_value("tags")).to eq(["tag1", "tag2"])
      end
    end

    it "can add a prefix to the tags" do
      config[:log_tag_prefix] = "sidekiq."
      job_logger.prepare(job) do
        expect(logger.tag_value("sidekiq.class")).to eq("MyWorker")
        expect(logger.tag_value("sidekiq.jid")).to eq("12345")
      end
    end

    it "can passthrough tags set from the tag passthrough middleware" do
      client_logger = Lumberjack::Logger.new(StringIO.new)
      middleware = Lumberjack::Sidekiq::TagPassthroughMiddleware.new(:user_id, :request_id)
      job["logging"] = {"tags" => {"user_id" => 123, "request_id" => "abc"}}
      allow(Sidekiq).to receive(:logger).and_return(client_logger)
      middleware.call("MyWorker", job, "default", nil) do
        job_logger.prepare(job) do
          expect(logger.tag_value("user_id")).to eq(123)
          expect(logger.tag_value("request_id")).to eq("abc")
        end
      end
    end

    it "can set the logging level with the log_level option" do
      job["log_level"] = "warn"
      job_logger.prepare(job) do
        expect(logger.level).to eq(Lumberjack::Logger::WARN)
      end
    end

    it "can set the logging level with the logging.level option" do
      job["logging"] = {"level" => "error"}
      job_logger.prepare(job) do
        expect(logger.level).to eq(Lumberjack::Logger::ERROR)
      end
    end
  end

  describe "#call" do
    it "has the same signature as the Sidekiq::JobLogger#call method" do
      job_logger = Sidekiq::JobLogger.new(config)
      value = nil
      job_logger.call(job, "default") do
        value = "foobar"
      end
      expect(value).to eq("foobar")
    end

    context "when logger is not a Lumberjack logger" do
      let(:logger) { Logger.new(out) }

      it "logs the start of the job" do
        value = nil
        job_logger.call(job, "default") do
          value = "foobar"
        end
        expect(value).to eq("foobar")
        expect(out.string).to include("Start Sidekiq job MyWorker.perform(1, 2, 3)")
      end

      it "logs the end of the job" do
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("Finished Sidekiq job MyWorker.perform(1, 2, 3)")
      end

      it "logs the failure of the job" do
        expect do
          job_logger.call(job, "default") do
            raise "Job failed"
          end
        end.to raise_error("Job failed")
        expect(out.string).to include("Failed Sidekiq job MyWorker.perform(1, 2, 3)")
      end
    end

    it "logs the start of the job with the queue name" do
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).to include("Start Sidekiq job MyWorker.perform(1, 2, 3)")
    end

    it "suppresses the start job log entry if the skip_start_job_logging config option is true" do
      config[:skip_start_job_logging] = true
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).not_to include("Start Sidekiq job")
    end

    it "suppressed the start job log entry if the logging.skip_start_job job option is true" do
      job["logging"] = {"skip_start" => true}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).not_to include("Start Sidekiq job")
    end

    it "suppresses the start job log entry if the logging.skip option is true" do
      job["logging"] = {"skip" => true}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).not_to include("Start Sidekiq job")
    end

    it "logs the end of the job with the queue name, duration" do
      job_logger.call(job, "default") do
        sleep(0.1)
      end
      expect(out.string).to include("Finished Sidekiq job MyWorker.perform(1, 2, 3)")
      expect(out.string).to match(/duration:\d{1,3}(\.\d{1,6})?/)
    end

    describe "enqueued time logging" do
      it "includes the enqueued time in milliseconds if enqueed_at is an integer" do
        job["enqueued_at"] = (Time.now.to_f * 1000).floor - 10
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to match(/enqueued_ms:\d{2}\b/)
      end

      it "includes the enqueued time in milliseconds if enqueued_at is a float" do
        job["enqueued_at"] = Time.now.to_f - 0.01
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to match(/enqueued_ms:\d{2}\b/)
      end

      it "does not log enqueued time if skip_enqueued_time_logging is true" do
        config[:skip_enqueued_time_logging] = true
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).not_to include("enqueued_ms:")
      end
    end

    it "suppresses the end job log entry if the logging.skip job option is true" do
      job["logging"] = {"skip" => true}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).not_to include("Finished Sidekiq job")
    end

    it "logs the failure of the job with the queue name and duration" do
      expect {
        job_logger.call(job, "default") do
          sleep(0.1)
          raise "Job failed"
        end
      }.to raise_error("Job failed")
      expect(out.string).to include("Failed Sidekiq job MyWorker.perform(1, 2, 3)")
      expect(out.string).to match(/duration:\d{1,3}(\.\d{1,6})?/)
    end

    it "suppresses the failure job log entry if the logging.skip job option is true" do
      job["logging"] = {"skip" => true}
      expect do
        job_logger.call(job, "default") do
          sleep(0.1)
          raise "Job failed"
        end
      end.to raise_error("Job failed")
      expect(out.string).not_to include("Failed Sidekiq job")
    end

    it "includes the retry count in the log entries if the job is being retried" do
      job["retry_count"] = 2
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).to include("retry_count:2")
    end

    it "does not include the retry count if it is zero" do
      job["retry_count"] = 0
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).not_to include("retry_count:")
    end

    it "includes current Sidekiq::Context in the log tags" do
      config[:tag_prefix] = "sidekiq."
      job_logger.call(job, "default") do
        Sidekiq::Context.current[:user_id] = 123
      end
      expect(out.string).to include("user_id:123")
    end

    it "displays the display class name in the log entries" do
      job["display_class"] = "MyDisplayWorker"
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).to include("Start Sidekiq job MyDisplayWorker.perform(1, 2, 3)")
    end

    it "displays the wrapped job class name for wrapped jobs" do
      job["wrapped"] = "MyWrappedWorker"
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(out.string).to include("Start Sidekiq job MyWrappedWorker.perform(1, 2, 3)")
    end

    describe "argument redaction" do
      it "can redact the job arguments in the log entries" do
        job["logging"] = {"args" => false}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("MyWorker.perform(...)")
      end

      it "can provide an allow list of job arguments to include in the logs" do
        job["logging"] = {"args" => ["arg1", "arg2"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("MyWorker.perform(1, 2, -)")
      end

      it "redacts all arguments if the worker does not exist" do
        job["class"] = "NonExistentWorker"
        job["logging"] = {"args" => ["arg1"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("NonExistentWorker.perform(...)")
      end

      it "gets the arg names from the non-display job class" do
        job["display_class"] = "MyDisplayWorker"
        job["logging"] = {"args" => ["arg1", "arg2"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("MyDisplayWorker.perform(1, 2, -)")
      end

      it "gets the arg names from the wrapped job class" do
        job["class"] = "ActiveJobWrapper"
        job["wrapped"] = "MyWorker"
        job["logging"] = {"args" => ["arg1", "arg2"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("MyWorker.perform(1, 2, -)")
      end

      it "does not log any arguments if skip_logging_job_arguments is true" do
        config[:skip_logging_job_arguments] = true
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string).to include("MyWorker")
        expect(out.string).not_to include(".perform")
      end
    end
  end
end
