# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::Sidekiq do
  describe "VERSION" do
    it "has a version number" do
      expect(Lumberjack::Sidekiq::VERSION).not_to be nil
    end
  end

  describe ".perform_parameters" do
    it "returns the perform method parameters for the job's worker class" do
      job = {"class" => "MyWorker"}
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to eq([[:req, :arg1], [:req, :arg2], [:req, :arg3]])
    end

    it "returns nil for wrapped jobs" do
      job = {"class" => "ActiveJobWrapper", "wrapped" => "MyWorker"}
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to be_nil
    end

    it "returns nil if the class name is not a valid constant name" do
      job = {"class" => "not.a.constant"}
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to be_nil
    end

    it "caches the parameters per class name" do
      stub_const("CacheTestWorker", Class.new {
        def perform(arg1)
        end
      })
      job = {"class" => "CacheTestWorker"}
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to eq([[:req, :arg1]])

      stub_const("CacheTestWorker", Class.new {
        def perform(arg1, arg2)
        end
      })
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to eq([[:req, :arg1]])
    end

    it "bypasses the cache in development mode" do
      stub_const("Rails", double(env: double(development?: true)))

      stub_const("ReloadTestWorker", Class.new {
        def perform(arg1)
        end
      })
      job = {"class" => "ReloadTestWorker"}
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to eq([[:req, :arg1]])

      stub_const("ReloadTestWorker", Class.new {
        def perform(arg1, arg2)
        end
      })
      expect(Lumberjack::Sidekiq.perform_parameters(job)).to eq([[:req, :arg1], [:req, :arg2]])
    end
  end
end
