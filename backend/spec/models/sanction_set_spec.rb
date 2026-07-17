# frozen_string_literal: true

require "rails_helper"

RSpec.describe SanctionSet do
  let(:wallpaper_allowed) { BetaEvents::SourceRegistry::WALLPAPER_ALLOWED }

  it "parses unified lock fields from flat legacy format" do
    sanction = described_class.from_hash(
      {
        "leverage_photo_lock_enabled" => true,
        "leverage_photo_lock_seconds" => 86_400,
        "leverage_photo_lock_target_mode" => "specific",
        "leverage_photo_lock_photo_id" => 42,
        "leverage_photo_delete_enabled" => true,
        "leverage_photo_delete_target_mode" => "random"
      },
      allowed: wallpaper_allowed
    )

    expect(sanction).to be_leverage_photo_lock_active
    expect(sanction.leverage_photo_lock_seconds).to eq(86_400)
    expect(sanction.leverage_photo_lock_target_mode).to eq("specific")
    expect(sanction.leverage_photo_lock_photo_id).to eq(42)
    expect(sanction).to be_leverage_photo_delete_active
    lock_item = sanction.to_h["items"].find { |i| i["possibility_id"] == "leverage_photo.lock" }
    expect(lock_item["config"]["photo_id"]).to eq(42)
  end

  it "coalesces legacy start/add_time into lock (start preferred)" do
    sanction = described_class.from_hash(
      {
        "leverage_photo_start_enabled" => true,
        "leverage_photo_start_seconds" => 86_400,
        "leverage_photo_start_target_mode" => "specific",
        "leverage_photo_start_photo_id" => 42,
        "leverage_photo_add_time_enabled" => true,
        "leverage_photo_add_time_seconds" => 3600,
        "leverage_photo_add_time_target_mode" => "random"
      },
      allowed: wallpaper_allowed
    )

    expect(sanction).to be_leverage_photo_lock_active
    expect(sanction.leverage_photo_lock_seconds).to eq(86_400)
    expect(sanction.leverage_photo_lock_target_mode).to eq("specific")
    expect(sanction.leverage_photo_lock_photo_id).to eq(42)
    expect(sanction.to_h["items"].map { |i| i["possibility_id"] }).to include("leverage_photo.lock")
  end

  it "falls back invalid target mode to random" do
    sanction = described_class.from_hash(
      {
        "leverage_photo_lock_enabled" => true,
        "leverage_photo_lock_seconds" => 60,
        "leverage_photo_lock_target_mode" => "nope"
      },
      allowed: wallpaper_allowed
    )
    expect(sanction.leverage_photo_lock_target_mode).to eq("random")
  end

  it "round-trips items format" do
    sanction = described_class.from_hash(
      {
        "items" => [
          { "possibility_id" => "chaster.add_time", "enabled" => true, "config" => { "seconds" => 120 } },
          { "possibility_id" => "pishock.shock", "enabled" => true, "config" => { "intensity" => 40, "duration" => 2 } }
        ]
      },
      allowed: wallpaper_allowed
    )

    expect(sanction).to be_chaster_add_time_active
    expect(sanction.chaster_seconds).to eq(120)
    expect(sanction).to be_pishock_active
    expect(sanction.pishock_intensity).to eq(40)
    expect(sanction.to_h["items"].size).to eq(wallpaper_allowed.size)
  end

  it "parses keyed form params" do
    sanction = described_class.from_params(
      {
        "chaster.add_time" => { "enabled" => "1", "seconds" => "600" },
        "chaster.freeze" => { "enabled" => "0" }
      },
      allowed: %w[chaster.add_time chaster.freeze]
    )

    expect(sanction).to be_chaster_add_time_active
    expect(sanction.chaster_seconds).to eq(600)
    expect(sanction).not_to be_chaster_freeze_active
  end
end
