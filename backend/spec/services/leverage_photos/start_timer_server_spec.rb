# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::StartTimerServer do
  let(:user) { create(:user, :beta) }
  let(:duration_seconds) { 3600 }

  def stub_encrypt_bytes!(round: 111)
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\nfresh\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  def stub_encrypt_outer_layer!(round: 222)
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_outer_layer).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\nwrapped\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  it "locks a draft photo using its plaintext original" do
    photo = create(:leverage_photo, :with_images, user: user)
    stub_encrypt_bytes!

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_bytes)
    photo.reload
    expect(photo.status).to eq("active")
    expect(photo.tlock_layer_count).to eq(1)
  end

  it "re-locks a photo that was unlocked, even though its plaintext original was already purged" do
    photo = create(:leverage_photo, :unlocked, user: user)
    expect(photo.original_image).not_to be_attached
    expect(photo.tlock_blob).to be_attached
    stub_encrypt_outer_layer!

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_outer_layer)
    photo.reload
    expect(photo.status).to eq("active")
    expect(photo.locked_until).to be_within(5.seconds).of(Time.current + duration_seconds.seconds)
  end

  it "raises when the photo is neither draft nor unlocked" do
    photo = create(:leverage_photo, :active, user: user)

    expect do
      described_class.new(photo: photo, duration_seconds: duration_seconds).call!
    end.to raise_error(described_class::Error, /cannot be locked/)
  end

  it "raises when no source image is available at all" do
    photo = create(:leverage_photo, :unlocked, user: user)
    photo.tlock_blob.purge

    expect do
      described_class.new(photo: photo, duration_seconds: duration_seconds).call!
    end.to raise_error(described_class::Error, /no source image/)
  end
end
