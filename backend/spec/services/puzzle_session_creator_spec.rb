# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuzzleSessionCreator do
  let(:user) { create(:user, :beta) }
  let!(:photo) { create(:leverage_photo, :with_images, user: user) }

  before do
    stub_beta_catalog_feature_flags("beta_source_puzzle" => true, "beta_action_puzzle" => true)
  end

  it "creates an assigned session from a leverage photo" do
    result = described_class.new(
      user: user,
      origin: "self",
      image_source: "leverage_photo",
      leverage_photo_id: photo.id,
      piece_count: 16
    ).call

    expect(result.ok).to eq(true)
    expect(result.session.piece_count).to eq(16)
    expect(result.session.grid_cols).to eq(4)
    expect(result.session.status).to eq("assigned")
    expect(result.session.leverage_photo_id).to eq(photo.id)
  end

  it "clamps piece counts into the allowed range" do
    result = described_class.new(
      user: user,
      image_source: "leverage_photo",
      leverage_photo_id: photo.id,
      piece_count: 20
    ).call

    expect(result.ok).to eq(true)
    expect(result.session.piece_count).to eq(20)

    high = described_class.new(
      user: user,
      image_source: "leverage_photo",
      leverage_photo_id: photo.id,
      piece_count: 999
    ).call
    expect(high.ok).to eq(true)
    expect(high.session.piece_count).to eq(PuzzleConfig::MAX_PIECE_COUNT)
  end
end
