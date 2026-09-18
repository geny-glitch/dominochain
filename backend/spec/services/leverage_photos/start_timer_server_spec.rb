# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::StartTimerServer do
  let(:user) { create(:user, :beta) }
  let(:duration_seconds) { 3600 }

  def stub_encrypt_attachment!(round: 111, armored: "fresh")
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\n#{armored}\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  it "locks a draft photo using its plaintext original" do
    photo = create(:leverage_photo, :with_images, user: user)
    stub_encrypt_attachment!

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_attachment).with(
      photo.original_image,
      kind_of(Time),
      command: "encrypt-bytes"
    )
    photo.reload
    expect(photo.status).to eq("active")
    expect(photo.tlock_layer_count).to eq(1)
  end

  it "re-locks a photo that was unlocked, even though its plaintext original was already purged" do
    photo = create(:leverage_photo, :unlocked, user: user)
    expect(photo.original_image).not_to be_attached
    expect(photo.tlock_blob).to be_attached
    stub_encrypt_attachment!(round: 222, armored: "wrapped")

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_attachment).with(
      photo.tlock_blob,
      kind_of(Time),
      command: "encrypt-outer"
    )
    photo.reload
    expect(photo.status).to eq("active")
    expect(photo.tlock_layer_count).to eq(2)
    expect(photo.locked_until).to be_within(5.seconds).of(Time.current + duration_seconds.seconds)
  end

  it "increments the layer count when wrapping an unlocked photo that already had nested layers" do
    photo = create(:leverage_photo, :unlocked, user: user, tlock_layer_count: 3)
    stub_encrypt_attachment!(round: 222, armored: "wrapped")

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(photo.reload.tlock_layer_count).to eq(4)
  end

  it "starts a fresh single layer when an unlocked photo has its original back" do
    photo = create(:leverage_photo, :unlocked, user: user)
    photo.tlock_blob.purge
    photo.original_image.attach(
      io: StringIO.new("restored-original"),
      filename: "original.jpg",
      content_type: "image/jpeg"
    )
    stub_encrypt_attachment!

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_attachment).with(
      photo.original_image,
      kind_of(Time),
      command: "encrypt-bytes"
    )
    expect(photo.reload.tlock_layer_count).to eq(1)
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
