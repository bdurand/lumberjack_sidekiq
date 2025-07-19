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
