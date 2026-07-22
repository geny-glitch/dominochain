# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "time zone" do
    it "defaults to Paris when omitted" do
      user = build(:user, time_zone: nil)

      expect(user).to be_valid
      expect(user.effective_time_zone).to eq("Paris")
    end

    it "preserves London instead of collapsing it to Edinburgh" do
      user = build(:user, time_zone: "London")

      expect(user).to be_valid
      expect(user.time_zone).to eq("London")
      expect(user.effective_time_zone).to eq("London")
    end

    it "maps IANA Europe/Paris to the selectable Paris name" do
      user = build(:user, time_zone: "Europe/Paris")

      expect(user).to be_valid
      expect(user.time_zone).to eq("Paris")
    end

    it "rejects unknown time zones" do
      user = build(:user, time_zone: "Mars/Olympus")

      expect(user).not_to be_valid
      expect(user.errors[:time_zone]).to be_present
    end

    it "syncs Strava and Chess.com goals when the account time zone changes" do
      user = create(:user, :beta, time_zone: "Paris")
      strava_goal = create(:strava_goal, user: user, time_zone: "Paris")
      chess_goal = create(:chess_com_goal, user: user, time_zone: "Paris")

      user.update!(time_zone: "Eastern Time (US & Canada)")

      expect(strava_goal.reload.time_zone).to eq("Eastern Time (US & Canada)")
      expect(chess_goal.reload.time_zone).to eq("Eastern Time (US & Canada)")
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
