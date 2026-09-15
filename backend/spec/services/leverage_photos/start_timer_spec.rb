# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::StartTimer do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }

  def start!(round: 99_001)
    described_class.new(
      photo: photo.reload,
      tlock_blob: { io: StringIO.new("AGE-#{round}"), filename: "layer.tlock", content_type: "text/plain" },
      drand_round: round,
      locked_until: 1.hour.from_now,
      duration_seconds: 1.hour.to_i
    ).call!
  end

  it "locks a draft photo" do
    start!

    photo.reload
    expect(photo).to be_active
    expect(photo.tlock_layer_count).to eq(1)
    expect(photo.original_image).not_to be_attached
  end

  it "rejects a second start once the photo is already active" do
    start!

    expect { start!(round: 99_002) }.to raise_error(described_class::Error, /cannot be locked/)
    expect(photo.reload.drand_rounds).to eq([99_001])
  end
end
