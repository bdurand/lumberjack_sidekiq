# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::Sidekiq do
  it "has a version number" do
    expect(Lumberjack::Sidekiq::VERSION).not_to be nil
  end
end
