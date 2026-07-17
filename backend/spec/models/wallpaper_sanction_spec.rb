# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperSanction do
  it "parses leverage photo fields from modern hash" do
    sanction = described_class.from_hash(
      "leverage_photo_start_enabled" => true,
      "leverage_photo_start_seconds" => 86_400,
      "leverage_photo_start_target_mode" => "specific",
      "leverage_photo_start_photo_id" => 42,
      "leverage_photo_add_time_enabled" => true,
      "leverage_photo_add_time_seconds" => 3600,
      "leverage_photo_add_time_target_mode" => "random",
      "leverage_photo_delete_enabled" => true,
      "leverage_photo_delete_target_mode" => "specific",
      "leverage_photo_delete_photo_id" => 7
    )

    expect(sanction).to be_leverage_photo_start_active
    expect(sanction.leverage_photo_start_seconds).to eq(86_400)
    expect(sanction.leverage_photo_start_target_mode).to eq("specific")
    expect(sanction.leverage_photo_start_photo_id).to eq(42)
    expect(sanction).to be_leverage_photo_add_time_active
    expect(sanction).to be_leverage_photo_delete_active
    expect(sanction.to_h["leverage_photo_start_photo_id"]).to eq(42)
    expect(sanction.to_h["leverage_photo_add_time_photo_id"]).to be_nil
  end

  it "defaults invalid target mode to random" do
    sanction = described_class.from_hash(
      "leverage_photo_start_enabled" => true,
      "leverage_photo_start_seconds" => 60,
      "leverage_photo_start_target_mode" => "nope"
    )
    expect(sanction.leverage_photo_start_target_mode).to eq("random")
  end
end
