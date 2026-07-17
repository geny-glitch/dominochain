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

  it "derives wallpaper form possibilities from accepted catalogs" do
    source = described_class.for_event_source(:wallpaper)
    expect(source.event(:mismatch_add_time).mode).to eq(:payload)
    expect(source.event(:mismatch_add_time).accepted_catalogs).to eq(described_class::WALLPAPER_CATALOGS)
    expect(described_class.allowed_for(:wallpaper, :mismatch_add_time)).to match_array(
      BetaEvents::ActionRegistry.user_configurable_ids(catalog_ids: described_class::WALLPAPER_CATALOGS)
    )
    expect(described_class.allowed_for(:wallpaper, :mismatch_add_time)).not_to include("chaster.unfreeze")
    expect(source.event(:enforcement_unfreeze).mode).to eq(:fixed)
  end

  it "lists strava form possibilities as leverage only, with chaster at runtime" do
    expect(described_class.allowed_for(:strava_goal, :failed_penalty)).to contain_exactly(
      "leverage_photo.lock",
      "leverage_photo.delete"
    )
    expect(described_class.runtime_allowed_for(:strava_goal, :failed_penalty)).to include(
      "chaster.add_time",
      "leverage_photo.lock",
      "leverage_photo.delete"
    )
  end

  it "binds cornertime movement events to payload sanctions" do
    source = described_class.for_event_source(:cornertime)
    event_def = source.event(:movement_detected)

    expect(event_def.mode).to eq(:payload)
    expect(event_def.accepted_catalogs).to eq(described_class::CORNERTIME_CATALOGS)
    expect(described_class.allowed_for(:cornertime, :movement_detected)).to include(
      "chaster.add_time",
      "pishock.shock",
      "leverage_photo.lock",
      "leverage_photo.delete"
    )
    expect(source.event(:early_stop).mode).to eq(:payload)
    expect(described_class.allowed_for(:cornertime, :early_stop)).to include("chaster.add_time")
  end
end
