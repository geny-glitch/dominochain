# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::SourceRegistry do
  it "binds showcase_game score to pishock + chaster with rate limit" do
    source = described_class.for_event_source(:showcase_game)
    event_def = source.event(:score_time_applied)

    expect(event_def.mode).to eq(:fixed)
    ids = event_def.bindings.map { |b| b[:possibility_id] }
    expect(ids).to eq(%w[pishock.shock chaster.add_time])
    chaster = event_def.bindings.find { |b| b[:possibility_id] == "chaster.add_time" }
    expect(chaster[:rate_limit]).to include(window_seconds: 300, max_seconds: 172_800)
  end

  it "exposes wallpaper allowed possibilities via default payload mode" do
    source = described_class.for_event_source(:wallpaper)
    expect(source.event(:mismatch_add_time).mode).to eq(:payload)
    expect(source.event(:mismatch_add_time).allowed).to eq(described_class::WALLPAPER_ALLOWED)
    expect(source.event(:enforcement_unfreeze).mode).to eq(:fixed)
  end

  it "lists strava leverage possibilities" do
    expect(described_class.allowed_for(:strava_goal, :failed_penalty)).to include(
      "chaster.add_time",
      "leverage_photo.lock",
      "leverage_photo.delete"
    )
  end
end
