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

  def stub_encrypt_bytes!(round:)
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\nkey\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  it "wraps the current lock payload and records the add-time base" do
    stub_encrypt_bytes!(round: 200_010)

    described_class.new(
      photo: photo,
      added_seconds: 3.days.to_i,
      save_as_base: true,
      apply_next_step: true
    ).call!

    photo.reload
    expect(photo.tlock_layer_count).to eq(1)
    expect(photo.add_time_base_seconds).to eq(3.days.to_i)
    expect(photo.add_time_step_n).to eq(1)
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    expect(photo.encrypted_original).to be_attached
    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_bytes)
  end

  it "wraps an envelope key blob with an outer tlock layer" do
    photo.update!(tlock_format: LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    photo.encrypted_original.attach(
      io: StringIO.new("packed-original"),
      filename: "original.bin",
      content_type: "application/octet-stream"
    )
    stub_encrypt_attachment!(round: 200_020)
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes)

    described_class.new(photo: photo, added_seconds: 1.hour.to_i).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_attachment).with(
      photo.tlock_blob,
      kind_of(Time),
      command: "encrypt-outer"
    )
    expect(LeveragePhotos::TlockCrypto).not_to have_received(:encrypt_bytes)
    photo.reload
    expect(photo.tlock_layer_count).to eq(2)
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
  end
end
