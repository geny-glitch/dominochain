# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::ActionRegistry do
  it "registers the six core possibilities" do
    expect(described_class.all.keys).to contain_exactly(
      "chaster.add_time",
      "chaster.freeze",
      "chaster.unfreeze",
      "pishock.shock",
      "leverage_photo.lock",
      "leverage_photo.delete"
    )
  end

  it "maps executors to catalog ids" do
    expect(described_class.catalog_id_for_executor(BetaEvents::Actions::ChasterAddTimeFromEvent)).to eq("chaster")
    expect(described_class.catalog_id_for_executor(BetaEvents::Actions::EnqueuePishockFromEvent)).to eq("pishock")
  end

  it "normalizes config with clamps and defaults" do
    config = described_class.normalize_config("pishock.shock", {})
    expect(config[:intensity]).to eq(50)
    expect(config[:duration]).to eq(1)

    clamped = described_class.normalize_config("pishock.shock", intensity: 999, duration: 0)
    expect(clamped[:intensity]).to eq(100)
    expect(clamped[:duration]).to eq(1)
  end

  it "maps legacy action strings" do
    expect(described_class.possibility_id_for_legacy_action("chaster_add_time")).to eq("chaster.add_time")
    expect(described_class.possibility_id_for_legacy_action("leverage_photo_start")).to eq("leverage_photo.lock")
    expect(described_class.legacy_action_for("pishock.shock")).to eq("pishock")
  end

  it "resolves showcase_score binding config" do
    event = BetaEvents::DomainEvent.new(
      beta: build_stubbed(:user),
      source: :showcase_game,
      kind: :score_time_applied,
      payload: { game_kind: "tetris", lines: 3, seconds: 180 }
    )
    binding = { possibility_id: "pishock.shock", config_resolver: :showcase_score }
    expect(described_class.resolve_binding_config(binding, event)).to eq(intensity: 3, duration: 3)
  end

  it "skips showcase_score for quiz" do
    event = BetaEvents::DomainEvent.new(
      beta: build_stubbed(:user),
      source: :showcase_game,
      kind: :score_time_applied,
      payload: { game_kind: "quiz", seconds: 10 }
    )
    binding = { possibility_id: "pishock.shock", config_resolver: :showcase_score }
    expect(described_class.resolve_binding_config(binding, event)).to be_nil
  end
end
