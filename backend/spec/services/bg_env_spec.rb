# frozen_string_literal: true

require "rails_helper"

RSpec.describe BgEnv do
  around do |example|
    previous = ENV["BG_ENV"]
    ENV.delete("BG_ENV")
    example.run
  ensure
    ENV.delete("BG_ENV")
    ENV["BG_ENV"] = previous if previous
  end

  describe ".posthog_value" do
    it "returns staging when BG_ENV is staging" do
      ENV["BG_ENV"] = "staging"
      expect(described_class.posthog_value).to eq("staging")
    end

    it "returns production in production mode without BG_ENV" do
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.posthog_value).to eq("production")
    end

    it "returns development outside production without BG_ENV" do
      allow(Rails.env).to receive(:production?).and_return(false)
      expect(described_class.posthog_value).to eq("development")
    end
  end

  describe ".staging?" do
    it "is true only for staging bg_env" do
      ENV["BG_ENV"] = "staging"
      expect(described_class.staging?).to eq(true)

      ENV["BG_ENV"] = "production"
      expect(described_class.staging?).to eq(false)
    end
  end
end
