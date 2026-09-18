# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::AddTimeServer do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :active, user: user) }

  def stub_encrypt_attachment!(round:)
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\nouter\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  it "wraps the current lock payload and records the add-time base" do
    stub_encrypt_attachment!(round: 200_010)

    described_class.new(
      photo: photo,
      added_seconds: 3.days.to_i,
      save_as_base: true,
      apply_next_step: true
    ).call!

    photo.reload
    expect(photo.tlock_layer_count).to eq(2)
    expect(photo.add_time_base_seconds).to eq(3.days.to_i)
    expect(photo.add_time_step_n).to eq(1)
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_FULL_IMAGE)
  end
end
