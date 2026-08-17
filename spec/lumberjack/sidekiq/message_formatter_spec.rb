# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::Sidekiq::MessageFormatter do
  let(:config) { ::Sidekiq::Config.new }
  let(:formatter) { described_class.new(config) }

  describe "#start_job" do
    it "formats the start job message with job info" do
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.start_job(job)).to eq("Start Sidekiq job MyWorker.perform(\"foo\", 12)")
    end
  end

  describe "#end_job" do
    it "formats the end job message with job info and elapsed time" do
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      elapsed_time = 0.12345
      expect(formatter.end_job(job, elapsed_time)).to eq("Finished Sidekiq job MyWorker.perform(\"foo\", 12) in 123.5ms")
    end
  end

  describe "#failed_job" do
    it "formats the failed job message with job info, error, and elapsed time" do
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      error = RuntimeError.new("Something went wrong")
      elapsed_time = 0.12345
      expect(formatter.failed_job(job, error, elapsed_time)).to eq("Failed Sidekiq job MyWorker.perform(\"foo\", 12) due to RuntimeError in 123.5ms")
    end
  end

  describe "message overrides" do
    let(:job) { {"class" => "MyWorker", "args" => ["foo", 12], "queue" => "default", "jid" => "abc123"} }

    it "overrides the start job message with a lambda" do
      config[:job_logger_messages] = {start: ->(job) { "Running #{job["class"]} on #{job["queue"]}" }}
      expect(formatter.start_job(job)).to eq("Running MyWorker on default")
    end

    it "overrides the end job message with a lambda" do
      config[:job_logger_messages] = {
        end: ->(job, elapsed_time) { "Completed #{job["jid"]} in #{(elapsed_time * 1000).round(1)}ms" }
      }
      expect(formatter.end_job(job, 0.12345)).to eq("Completed abc123 in 123.5ms")
    end

    it "overrides the failed job message with a lambda" do
      config[:job_logger_messages] = {
        failed: ->(job, error, elapsed_time) { "#{job["jid"]} raised #{error.class.name}: #{error.message} after #{elapsed_time}s" }
      }
      error = RuntimeError.new("Something went wrong")
      expect(formatter.failed_job(job, error, 0.12345)).to eq("abc123 raised RuntimeError: Something went wrong after 0.12345s")
    end

    it "evaluates the lambda in the context of the formatter so helper methods are available" do
      config[:job_logger_messages] = {start: ->(job) { "Running #{job_info(job)} (#{worker_class(job)})" }}
      expect(formatter.start_job(job)).to eq("Running MyWorker.perform(\"foo\", 12) (MyWorker)")
    end

    it "only passes the arguments a lambda declares" do
      config[:job_logger_messages] = {
        end: ->(job) { "Completed #{job_info(job)}" },
        failed: ->(job, error) { "Failed #{job_info(job)} with #{error.class.name}" }
      }
      expect(formatter.end_job(job, 0.12345)).to eq("Completed MyWorker.perform(\"foo\", 12)")
      expect(formatter.failed_job(job, RuntimeError.new("boom"), 0.12345)).to eq("Failed MyWorker.perform(\"foo\", 12) with RuntimeError")
    end

    it "supports procs as well as lambdas" do
      config[:job_logger_messages] = {start: proc { |job| "Running #{job_info(job)}" }}
      expect(formatter.start_job(job)).to eq("Running MyWorker.perform(\"foo\", 12)")
    end

    it "supports any object that responds to call" do
      callable = Class.new do
        def call(job)
          "Running #{job["class"]}"
        end
      end.new
      config[:job_logger_messages] = {start: callable}
      expect(formatter.start_job(job)).to eq("Running MyWorker")
    end

    it "only passes the arguments a callable object declares" do
      callable = Class.new do
        def call(job)
          "Completed #{job["class"]}"
        end
      end.new
      config[:job_logger_messages] = {end: callable}
      expect(formatter.end_job(job, 0.12345)).to eq("Completed MyWorker")
    end

    it "supports string keys for the message names" do
      config[:job_logger_messages] = {"start" => ->(job) { "Running #{job_info(job)}" }}
      expect(formatter.start_job(job)).to eq("Running MyWorker.perform(\"foo\", 12)")
    end

    it "uses the default messages for names that are not overridden" do
      config[:job_logger_messages] = {start: ->(job) { "Running #{job_info(job)}" }}
      expect(formatter.end_job(job, 0.12345)).to eq("Finished Sidekiq job MyWorker.perform(\"foo\", 12) in 123.5ms")
    end

    it "uses the default messages when the option is not a hash" do
      config[:job_logger_messages] = "invalid"
      expect(formatter.start_job(job)).to eq("Start Sidekiq job MyWorker.perform(\"foo\", 12)")
    end

    it "raises an error if a configured message does not respond to call" do
      config[:job_logger_messages] = {start: "Running {job}"}
      expect { formatter }.to raise_error(ArgumentError, /job_logger_messages\[:start\] must respond to `call`/)
    end
  end

  describe "#job_info" do
    it "returns the formatted job information with arguments" do
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.job_info(job)).to eq("MyWorker.perform(\"foo\", 12)")
    end

    it "handles empty arguments" do
      job = {"class" => "MyWorker", "args" => []}
      expect(formatter.job_info(job)).to eq("MyWorker.perform()")
    end

    it "handles nil arguments" do
      job = {"class" => "MyWorker", "args" => nil}
      expect(formatter.job_info(job)).to eq("MyWorker.perform()")
    end

    it "omits all arguments if skip_logging_job_arguments? is true" do
      config[:skip_logging_job_arguments] = true
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.job_info(job)).to eq("MyWorker")
    end
  end

  describe "#job_display_args" do
    it "returns the formatted job arguments for logging" do
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.job_display_args(job)).to eq(['"foo"', "12"])
    end

    it "returns an empty array if args are nil" do
      job = {"class" => "MyWorker", "args" => nil}
      expect(formatter.job_display_args(job)).to eq([])
    end

    it "returns ['...'] if logging.args is false" do
      job = {"class" => "MyWorker", "args" => [], "logging" => {"args" => false}}
      expect(formatter.job_display_args(job)).to eq(["..."])
    end

    it "filters args based on logging.args option" do
      job = {"class" => "MyWorker", "args" => ["foo", 12], "logging" => {"args" => ["arg1"]}}
      expect(formatter.job_display_args(job)).to eq(['"foo"', "-"])
    end

    it "does not error if the logging option is not a hash" do
      job = {"class" => "MyWorker", "args" => ["foo", 12], "logging" => false}
      expect(formatter.job_display_args(job)).to eq(['"foo"', "12"])
    end

    describe "truncation" do
      it "keeps values that are not longer than the maximum length" do
        value = "a" * described_class::MAX_ARG_LENGTH
        job = {"class" => "MyWorker", "args" => [value]}
        expect(formatter.job_display_args(job)).to eq([value.inspect])
      end

      it "truncates long string values and keeps the quotes balanced" do
        job = {"class" => "MyWorker", "args" => ["a" * 100]}
        expected = "\"#{"a" * (described_class::MAX_ARG_LENGTH - 1)}…\""
        expect(formatter.job_display_args(job)).to eq([expected])
      end

      it "truncates long string values that contain escaped characters" do
        job = {"class" => "MyWorker", "args" => ["a\nb" * 100]}
        display_arg = formatter.job_display_args(job).first
        expect(display_arg).to start_with('"a\nb')
        expect(display_arg).to end_with("…\"")
      end

      it "truncates long values that are not strings" do
        job = {"class" => "MyWorker", "args" => [Array.new(100, 1)]}
        display_arg = formatter.job_display_args(job).first
        expect(display_arg.length).to eq(described_class::MAX_ARG_LENGTH)
        expect(display_arg).to start_with("[1, 1, 1,")
        expect(display_arg).to end_with("…")
      end

      it "truncates values in the args allow-list" do
        job = {"class" => "MyWorker", "args" => ["a" * 100, 12], "logging" => {"args" => ["arg1"]}}
        expected = "\"#{"a" * (described_class::MAX_ARG_LENGTH - 1)}…\""
        expect(formatter.job_display_args(job)).to eq([expected, "-"])
      end

      it "truncates values that are not hidden by the hide_args deny-list" do
        job = {"class" => "MyWorker", "args" => ["a" * 100, 12], "logging" => {"hide_args" => ["arg2"]}}
        expected = "\"#{"a" * (described_class::MAX_ARG_LENGTH - 1)}…\""
        expect(formatter.job_display_args(job)).to eq([expected, "-"])
      end
    end

    describe "hide_args deny-list" do
      it "hides args named in the logging.hide_args option" do
        job = {"class" => "MyWorker", "args" => ["foo", 12], "logging" => {"hide_args" => ["arg1"]}}
        expect(formatter.job_display_args(job)).to eq(["-", "12"])
      end

      it "hides args by zero based position" do
        job = {"class" => "MyWorker", "args" => ["foo", 12, 13], "logging" => {"hide_args" => [1]}}
        expect(formatter.job_display_args(job)).to eq(['"foo"', "-", "13"])
      end

      it "hides all arguments if the worker class cannot be resolved" do
        job = {"class" => "NoSuchWorkerClass", "args" => ["foo", 12], "logging" => {"hide_args" => ["arg1"]}}
        expect(formatter.job_display_args(job)).to eq(["..."])
      end

      it "gives precedence to the args allow-list when both options are set" do
        job = {"class" => "MyWorker", "args" => ["foo", 12], "logging" => {"args" => ["arg1"], "hide_args" => ["arg1"]}}
        expect(formatter.job_display_args(job)).to eq(['"foo"', "-"])
      end

      it "applies the deny-list when the args option is true" do
        job = {"class" => "MyWorker", "args" => ["foo", 12], "logging" => {"args" => true, "hide_args" => ["arg1"]}}
        expect(formatter.job_display_args(job)).to eq(["-", "12"])
      end

      it "hides all values of a splat parameter" do
        job = {"class" => "MySplatWorker", "args" => ["foo", 12, 13], "logging" => {"hide_args" => ["rest"]}}
        expect(formatter.job_display_args(job)).to eq(['"foo"', "-", "-"])
      end

      it "hides all arguments for wrapped jobs since the arg names cannot be resolved" do
        job = {"class" => "ActiveJobWrapper", "wrapped" => "MyWorker", "args" => [{"arguments" => ["foo", 12]}], "logging" => {"hide_args" => ["arg1"]}}
        expect(formatter.job_display_args(job)).to eq(["..."])
      end
    end
  end

  describe "#skip_logging_job_arguments?" do
    it "returns true if skip_logging_job_arguments is set in config" do
      config[:skip_logging_job_arguments] = true
      expect(formatter.skip_logging_job_arguments?).to be true
    end

    it "returns false if skip_logging_job_arguments is not set in config" do
      expect(formatter.skip_logging_job_arguments?).to be false
    end
  end

  describe "#worker_class" do
    it "returns the worker class from the job data" do
      job = {"class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.worker_class(job)).to eq("MyWorker")
    end

    it "returns the display_class if available" do
      job = {"display_class" => "MyDisplayWorker", "class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.worker_class(job)).to eq("MyDisplayWorker")
    end

    it "returns the wrapped class if available" do
      job = {"wrapped" => "MyWrappedWorker", "class" => "MyWorker", "args" => ["foo", 12]}
      expect(formatter.worker_class(job)).to eq("MyWrappedWorker")
    end
  end
end
