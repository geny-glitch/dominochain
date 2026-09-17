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

  it "clears the add-time step when a new lock starts" do
    unlocked = create(
      :leverage_photo,
      :unlocked,
      user: user,
      add_time_base_seconds: 3.days.to_i,
      add_time_step_n: 4
    )

    described_class.new(
      photo: unlocked,
      tlock_blob: { io: StringIO.new("AGE-relock"), filename: "layer.tlock", content_type: "text/plain" },
      drand_round: 99_101,
      locked_until: 1.hour.from_now,
      duration_seconds: 1.hour.to_i
    ).call!

    unlocked.reload
    expect(unlocked.add_time_base_seconds).to be_nil
    expect(unlocked.add_time_step_n).to eq(0)
  end
end
