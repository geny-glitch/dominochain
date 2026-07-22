# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::ScenarioRegistry do
  it "lists events per source" do
    expect(described_class.event_ids(:wallpaper)).to include("mismatch", "permissions_lost", "app_unreachable")
    expect(described_class.event_ids(:cornertime)).to contain_exactly("movement_detected", "early_stop")
    expect(described_class.event_ids(:strava)).to contain_exactly("any_goal_failed", "goal_failed")
    expect(described_class.event_ids(:chess)).to contain_exactly("any_goal_failed", "goal_failed")
  end

  it "resolves source from event id" do
    expect(described_class.source_for_event("mismatch")).to eq("wallpaper")
    expect(described_class.source_for_event("movement_detected")).to eq("cornertime")
    expect(described_class.source_for_event("any_goal_failed")).to eq("strava")
    expect(described_class.source_for_event("goal_failed")).to eq("strava")
  end

  it "returns allowed actions for each source" do
    expect(described_class.allowed_actions_for(:cornertime)).to include("chaster.add_time", "pishock.shock")
    expect(described_class.allowed_actions_for(:strava)).to include("chaster.add_time", "leverage_photo.lock")
    expect(described_class.allowed_actions_for(:chess)).to include("chaster.add_time", "leverage_photo.lock")
  end
end
