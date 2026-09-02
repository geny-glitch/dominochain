# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::AddTime do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :active, user: user) }

  def add!(locked_until:, round:)
    described_class.new(
      photo: photo.reload,
      tlock_blob: { io: StringIO.new("OUTER-#{round}"), filename: "layer.tlock", content_type: "text/plain" },
      drand_round: round,
      locked_until: locked_until,
      added_seconds: 3600
    ).call!
  end

  it "nests a layer and records the new round" do
    new_until = photo.locked_until + 1.hour

    add!(locked_until: new_until, round: 200_000)

    photo.reload
    expect(photo.tlock_layer_count).to eq(2)
    expect(photo.drand_rounds).to eq([12_345, 200_000])
    expect(photo.locked_until).to be_within(1.second).of(new_until)
  end

  it "rejects a second extend that does not move the expiry forward" do
    new_until = photo.locked_until + 1.hour
    add!(locked_until: new_until, round: 200_000)

    expect do
      add!(locked_until: new_until, round: 200_001)
    end.to raise_error(described_class::Error, /invalid locked_until/)

    expect(photo.reload.tlock_layer_count).to eq(2)
  end
end
