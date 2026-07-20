# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "time zone" do
    it "defaults to Europe/Paris when omitted" do
      user = build(:user, time_zone: nil)

      expect(user).to be_valid
      expect(user.effective_time_zone).to eq("Europe/Paris")
    end

    it "rejects unknown time zones" do
      user = build(:user, time_zone: "Mars/Olympus")

      expect(user).not_to be_valid
      expect(user.errors.full_messages).to include("Time zone est invalide")
    end
  end

  describe "#posthog_properties" do
    it "includes bg_env for PostHog feature flag targeting" do
      user = build(:user, :beta)
      allow(BgEnv).to receive(:posthog_value).and_return("staging")

      expect(user.posthog_properties[:bg_env]).to eq("staging")
    end
  end
end
