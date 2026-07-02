# frozen_string_literal: true

require "rails_helper"

RSpec.describe PosthogProductAnalytics do
  let(:user) { create(:user, :beta) }

  describe ".time_added_reason" do
    it "builds a showcase game reason from metadata" do
      reason = described_class.time_added_reason(
        source: "showcase_game",
        metadata: { "game_kind" => "dino" }
      )

      expect(reason).to eq("showcase_game:dino")
    end

    it "uses enforcement kind for wallpaper events" do
      reason = described_class.time_added_reason(
        source: "wallpaper",
        metadata: { "enforcement_kind" => "mismatch_add_time" }
      )

      expect(reason).to eq("mismatch_add_time")
    end
  end

  describe ".capture helpers" do
    it "sends activated_source with the source name" do
      described_class.activated_source(user, name: "wallpaper")

      expect(PostHog).to have_received(:capture).with(
        distinct_id: user.posthog_distinct_id,
        event: "activated_source",
        properties: { name: "wallpaper" }
      )
    end

    it "sends time_added with seconds and reason" do
      described_class.time_added(user, seconds: 120, reason: "puryfi", source: "puryfi")

      expect(PostHog).to have_received(:capture).with(
        distinct_id: user.posthog_distinct_id,
        event: "time_added",
        properties: { seconds: 120, reason: "puryfi", source: "puryfi" }
      )
    end
  end
end
