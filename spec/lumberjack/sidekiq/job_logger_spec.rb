# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::Sidekiq::JobLogger do
  let(:logger) { Lumberjack::Logger.new(:test) }
  let(:device) { logger.device }
  let(:config) { Sidekiq::Config.new.tap { |c| c.logger = logger } }
  let(:job_logger) { Lumberjack::Sidekiq::JobLogger.new(config) }
  let(:job) { {"class" => "MyWorker", "args" => [1, 2, 3], "jid" => "12345", "queue" => "default"} }

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
      let(:logger) { ::Logger.new(StringIO.new) }

      it "does not error if the logger is not a Lumberjack logger" do
        allow(Sidekiq).to receive(:logger).and_return(::Logger.new(StringIO.new))
        value = nil
        job_logger.prepare(job) do
          value = "foobar"
        end
        expect(value).to eq("foobar")
      end
    end

    it "adds attributes with the jid and class of the job" do
      job_logger.prepare(job) do
        expect(logger.attribute_value("jid")).to eq("12345")
        expect(logger.attribute_value("class")).to eq("MyWorker")
      end
    end

    it "adds attributes with the bid if present" do
      job["bid"] = "67890"
      job_logger.prepare(job) do
        expect(logger.attribute_value("bid")).to eq("67890")
      end
    end

    it "adds attributes with the job's custom attributes" do
      job["attributes"] = ["attribute1", "attribute2"]
      job_logger.prepare(job) do
        expect(logger.attribute_value("attributes")).to eq(["attribute1", "attribute2"])
      end
    end

    it "can add a prefix to the attributes" do
      config[:log_attribute_prefix] = "sidekiq."
      job_logger.prepare(job) do
        expect(logger.attribute_value("sidekiq.class")).to eq("MyWorker")
        expect(logger.attribute_value("sidekiq.jid")).to eq("12345")
      end
    end

    it "can passthrough attributes set from the attribute passthrough middleware" do
      client_logger = Lumberjack::Logger.new(:test)
      middleware = Lumberjack::Sidekiq::AttributePassthroughMiddleware.new(:user_id, :request_id)
      job["logging"] = {"attributes" => {"user_id" => 123, "request_id" => "abc"}}
      allow(Sidekiq).to receive(:logger).and_return(client_logger)
      middleware.call("MyWorker", job, "default", nil) do
        job_logger.prepare(job) do
          expect(logger.attribute_value("user_id")).to eq(123)
          expect(logger.attribute_value("request_id")).to eq("abc")
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

    it "does not error if the logging option is not a hash" do
      job["logging"] = false
      value = nil
      job_logger.prepare(job) do
        value = "foobar"
      end
      expect(value).to eq("foobar")
    end

    context "when using lumberjack_rails" do
      let(:broadcast_logger) { ActiveSupport::BroadcastLogger.new(logger) }
      let(:config) { Sidekiq::Config.new.tap { |c| c.logger = broadcast_logger } }

      it "adds attributes to the logger" do
        skip("lumberjack_rails not loaded") unless defined?(Lumberjack::Rails)

        job_logger.prepare(job) do
          expect(logger.attribute_value("jid")).to eq("12345")
          expect(logger.attribute_value("class")).to eq("MyWorker")
        end
      end
    end

    describe "arg attributes" do
      it "maps job arguments to attributes with the logging.arg_attributes option" do
        job["logging"] = {"arg_attributes" => {"arg1" => "first.arg", "arg3" => "third.arg"}}
        job_logger.prepare(job) do
          expect(logger.attribute_value("first.arg")).to eq(1)
          expect(logger.attribute_value("third.arg")).to eq(3)
        end
      end

      it "maps job arguments to attributes with the global arg_attributes config option" do
        config[:arg_attributes] = {arg2: "second.arg"}
        job_logger.prepare(job) do
          expect(logger.attribute_value("second.arg")).to eq(2)
        end
      end

      it "merges worker options over the global mapping" do
        config[:arg_attributes] = {arg1: "global.arg"}
        job["logging"] = {"arg_attributes" => {"arg1" => "worker.arg"}}
        job_logger.prepare(job) do
          expect(logger.attribute_value("worker.arg")).to eq(1)
          expect(logger.attribute_value("global.arg")).to be_nil
        end
      end

      it "does not prefix the mapped attribute names" do
        config[:log_attribute_prefix] = "sidekiq."
        job["logging"] = {"arg_attributes" => {"arg1" => "first.arg"}}
        job_logger.prepare(job) do
          expect(logger.attribute_value("first.arg")).to eq(1)
          expect(logger.attribute_value("sidekiq.first.arg")).to be_nil
        end
      end

      it "ignores arguments that are not perform parameters" do
        job["logging"] = {"arg_attributes" => {"missing" => "missing.arg"}}
        job_logger.prepare(job) do
          expect(logger.attribute_value("missing.arg")).to be_nil
        end
      end

      it "ignores the mapping if the worker class cannot be resolved" do
        job["class"] = "NoSuchWorkerClass"
        job["logging"] = {"arg_attributes" => {"arg1" => "first.arg"}}
        value = nil
        job_logger.prepare(job) do
          value = logger.attribute_value("first.arg")
        end
        expect(value).to be_nil
      end

      it "ignores the mapping for wrapped jobs since the arg names cannot be resolved" do
        job["class"] = "ActiveJobWrapper"
        job["wrapped"] = "MyWorker"
        job["logging"] = {"arg_attributes" => {"arg1" => "first.arg"}}
        value = nil
        job_logger.prepare(job) do
          value = logger.attribute_value("first.arg")
        end
        expect(value).to be_nil
      end

      it "maps a splat parameter to all of the remaining arguments" do
        job["class"] = "MySplatWorker"
        job["logging"] = {"arg_attributes" => {"rest" => "rest.args"}}
        job_logger.prepare(job) do
          expect(logger.attribute_value("rest.args")).to eq([2, 3])
        end
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
      let(:out) { StringIO.new }
      let(:logger) do
        ::Logger.new(out, formatter: ->(severity, _time, _progname, message) { "#{severity}: #{message}\n" })
      end

      it "logs the start of the job" do
        value = nil
        job_logger.call(job, "default") do
          value = "foobar"
        end
        expect(value).to eq("foobar")
        expect(out.string.lines.map(&:chomp)).to include("INFO: Start Sidekiq job MyWorker.perform(1, 2, 3)")
      end

      it "logs the end of the job" do
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(out.string.lines.map(&:chomp)).to include(
          a_string_matching(/\AINFO: Finished Sidekiq job MyWorker\.perform\(1, 2, 3\) in [\d.]+ms\z/)
        )
      end

      it "logs the failure of the job" do
        expect do
          job_logger.call(job, "default") do
            raise "Job failed"
          end
        end.to raise_error("Job failed")
        expect(out.string.lines.map(&:chomp)).to include(
          a_string_matching(/\AERROR: Failed Sidekiq job MyWorker\.perform\(1, 2, 3\) due to RuntimeError in [\d.]+ms\z/)
        )
      end
    end

    it "logs the start of the job with the queue name" do
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device).to include(
        severity: :info,
        message: "Start Sidekiq job MyWorker.perform(1, 2, 3)",
        attributes: {"queue" => "default"}
      )
    end

    it "suppresses the start job log entry if the skip_start_job_logging config option is true" do
      config[:skip_start_job_logging] = true
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device).not_to include(message: /\AStart Sidekiq job/)
      expect(device).to include(message: /\AFinished Sidekiq job/)
    end

    it "suppresses the start job log entry if the logging.skip_start_job job option is true" do
      job["logging"] = {"skip_start" => true}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device).not_to include(message: /\AStart Sidekiq job/)
      expect(device).to include(message: /\AFinished Sidekiq job/)
    end

    it "suppresses the start job log entry if the formatter has no start message in the formatter" do
      config[:job_logger_messages] = {start: ->(_job) {}}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device.entries.size).to eq(1)
      expect(device).to include(message: /\AFinished Sidekiq job/)
    end

    it "suppresses the start job log entry if the logging.skip option is true" do
      job["logging"] = {"skip" => true}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device.entries).to be_empty
    end

    it "logs the end of the job with the queue name, duration" do
      job_logger.call(job, "default") do
        sleep(0.01)
      end
      expect(device).to include(
        severity: :info,
        message: /\AFinished Sidekiq job MyWorker\.perform\(1, 2, 3\) in [\d.]+ms\z/,
        attributes: {"queue" => "default", "duration" => (be >= 0.01)}
      )
    end

    context "when using lumberjack_rails" do
      let(:broadcast_logger) { ActiveSupport::BroadcastLogger.new(logger) }
      let(:config) { Sidekiq::Config.new.tap { |c| c.logger = broadcast_logger } }

      it "logs the start job log entry" do
        job_logger.call(job, "default") do
          sleep(0.01)
        end
        expect(device).to include(
          severity: :info,
          message: /Start Sidekiq job MyWorker/,
          attributes: {"queue" => "default"}
        )
      end

      it "logs the end job log entry" do
        job_logger.call(job, "default") do
          sleep(0.01)
        end
        expect(device).to include(
          severity: :info,
          message: /Finished Sidekiq job MyWorker/,
          attributes: {"queue" => "default", "duration" => (be >= 0.01)}
        )
      end

      it "logs the failed job log entry" do
        expect {
          job_logger.call(job, "default") do
            sleep(0.01)
            raise "Job failed"
          end
        }.to raise_error("Job failed")
        expect(device).to include(
          severity: :error,
          message: /\Failed Sidekiq job MyWorker/,
          attributes: {"queue" => "default", "duration" => (be >= 0.01)}
        )
      end
    end

    describe "enqueued time logging" do
      it "includes the enqueued time in milliseconds if enqueed_at is an integer" do
        job["enqueued_at"] = (Time.now.to_f * 1000).floor - 10
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(
          message: /\AFinished Sidekiq job/,
          attributes: {"enqueued_ms" => (be >= 10)}
        )
      end

      it "includes the enqueued time in milliseconds if enqueued_at is a float" do
        job["enqueued_at"] = Time.now.to_f - 0.01
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(
          message: /\AFinished Sidekiq job/,
          attributes: {"enqueued_ms" => (be >= 10)}
        )
      end

      it "does not log enqueued time if skip_enqueued_time_logging is true" do
        config[:skip_enqueued_time_logging] = true
        job["enqueued_at"] = (Time.now.to_f * 1000).floor - 10
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device.last_entry.attributes).not_to have_key("enqueued_ms")
      end
    end

    it "suppresses the end job log entry if the logging.skip job option is true" do
      job["logging"] = {"skip" => true}
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device.entries).to be_empty
    end

    it "logs the failure of the job with the queue name and duration" do
      expect {
        job_logger.call(job, "default") do
          sleep(0.01)
          raise "Job failed"
        end
      }.to raise_error("Job failed")
      expect(device).to include(
        severity: :error,
        message: /\AFailed Sidekiq job MyWorker\.perform\(1, 2, 3\) due to RuntimeError in [\d.]+ms\z/,
        attributes: {"queue" => "default", "duration" => (be >= 0.01)}
      )
    end

    it "suppresses the failure job log entry if the logging.skip job option is true" do
      job["logging"] = {"skip" => true}
      expect do
        job_logger.call(job, "default") do
          raise "Job failed"
        end
      end.to raise_error("Job failed")
      expect(device.entries).to be_empty
    end

    describe "retry error handling" do
      it "logs the original error when the retry handler wraps it" do
        expect do
          job_logger.call(job, "default") do
            raise ArgumentError, "Job failed"
          rescue => e
            raise Sidekiq::JobRetry::Handled, e.message
          end
        end.to raise_error(Sidekiq::JobRetry::Handled)
        expect(device).to include(
          severity: :error,
          message: /\AFailed Sidekiq job MyWorker\.perform\(1, 2, 3\) due to ArgumentError in [\d.]+ms\z/
        )
        expect(device).not_to include(message: /Sidekiq::JobRetry::Handled/)
      end

      it "logs the wrapping error when it has no cause" do
        expect do
          job_logger.call(job, "default") do
            raise Sidekiq::JobRetry::Handled, "Job failed"
          end
        end.to raise_error(Sidekiq::JobRetry::Handled)
        expect(device).to include(
          severity: :error,
          message: /\AFailed Sidekiq job MyWorker\.perform\(1, 2, 3\) due to Sidekiq::JobRetry::Handled in [\d.]+ms\z/
        )
      end

      it "logs the job as failed when the job raises Sidekiq::JobRetry::Skip" do
        expect do
          job_logger.call(job, "default") do
            raise Sidekiq::JobRetry::Skip, "interrupted"
          end
        end.to raise_error(Sidekiq::JobRetry::Skip)
        expect(device).to include(
          severity: :error,
          message: /\AFailed Sidekiq job MyWorker\.perform\(1, 2, 3\) due to Sidekiq::JobRetry::Skip in [\d.]+ms\z/
        )
      end

      it "logs the original error when Skip wraps it" do
        expect do
          job_logger.call(job, "default") do
            raise ArgumentError, "Job failed"
          rescue
            raise Sidekiq::JobRetry::Skip, "interrupted"
          end
        end.to raise_error(Sidekiq::JobRetry::Skip)
        expect(device).to include(
          severity: :error,
          message: /\AFailed Sidekiq job MyWorker\.perform\(1, 2, 3\) due to ArgumentError in [\d.]+ms\z/
        )
      end

      it "does not log a failure for Skip if the logging.skip job option is true" do
        job["logging"] = {"skip" => true}
        expect do
          job_logger.call(job, "default") do
            raise Sidekiq::JobRetry::Skip, "interrupted"
          end
        end.to raise_error(Sidekiq::JobRetry::Skip)
        expect(device.entries).to be_empty
      end
    end

    it "includes the retry count in the log entries if the job is being retried" do
      job["retry_count"] = 2
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device.entries.size).to eq(2)
      expect(device.entries.map(&:attributes)).to all(include("retry_count" => 2))
    end

    it "includes the retry count if it is zero since that indicates the first retry" do
      job["retry_count"] = 0
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device.entries.map(&:attributes)).to all(include("retry_count" => 0))
    end

    it "logs the same duration in the message and the duration attribute" do
      job_logger.call(job, "default") do
        sleep(0.01)
      end
      entry = device.last_entry
      message_ms = entry.message[/ in ([\d.]+)ms\z/, 1].to_f
      expect((entry.attributes["duration"] * 1000).round(1)).to eq(message_ms)
    end

    it "includes current Sidekiq::Context in the log attributes" do
      Sidekiq::Context.with({}) do
        job_logger.call(job, "default") do
          Sidekiq::Context.current[:user_id] = 123
        end
      end
      expect(device).to include(
        message: /\AFinished Sidekiq job/,
        attributes: {"user_id" => 123}
      )
    end

    it "prefixes the job attributes with the log_attribute_prefix option" do
      config[:log_attribute_prefix] = "sidekiq."
      job["retry_count"] = 1
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device).to include(
        message: /\AFinished Sidekiq job/,
        attributes: {
          "sidekiq.queue" => "default",
          "sidekiq.retry_count" => 1,
          "sidekiq.duration" => (be_a Float)
        }
      )
    end

    it "displays the display class name in the log entries" do
      job["display_class"] = "MyDisplayWorker"
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device).to include(message: "Start Sidekiq job MyDisplayWorker.perform(1, 2, 3)")
    end

    it "displays the wrapped job class name for wrapped jobs" do
      job["wrapped"] = "MyWrappedWorker"
      job_logger.call(job, "default") do
        # Simulate job processing
      end
      expect(device).to include(message: "Start Sidekiq job MyWrappedWorker.perform(1, 2, 3)")
    end

    describe "argument redaction" do
      it "can redact the job arguments in the log entries" do
        job["logging"] = {"args" => false}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(message: "Start Sidekiq job MyWorker.perform(...)")
      end

      it "can provide an allow list of job arguments to include in the logs" do
        job["logging"] = {"args" => ["arg1", "arg2"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(message: "Start Sidekiq job MyWorker.perform(1, 2, -)")
      end

      it "redacts all arguments if the worker does not exist" do
        job["class"] = "NonExistentWorker"
        job["logging"] = {"args" => ["arg1"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(message: "Start Sidekiq job NonExistentWorker.perform(...)")
      end

      it "gets the arg names from the non-display job class" do
        job["display_class"] = "MyDisplayWorker"
        job["logging"] = {"args" => ["arg1", "arg2"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(message: "Start Sidekiq job MyDisplayWorker.perform(1, 2, -)")
      end

      it "redacts all arguments for wrapped jobs since the arg names cannot be resolved" do
        job["class"] = "ActiveJobWrapper"
        job["wrapped"] = "MyWorker"
        job["logging"] = {"args" => ["arg1", "arg2"]}
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(message: "Start Sidekiq job MyWorker.perform(...)")
      end

      it "does not log any arguments if skip_logging_job_arguments is true" do
        config[:skip_logging_job_arguments] = true
        job_logger.call(job, "default") do
          # Simulate job processing
        end
        expect(device).to include(message: "Start Sidekiq job MyWorker")
      end
    end
  end
end
