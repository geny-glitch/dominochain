# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::StartTimerServer do
  let(:user) { create(:user, :beta) }
  let(:duration_seconds) { 3600 }

  def stub_encrypt_bytes!(round: 111, armored: "fresh")
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\n#{armored}\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  def stub_encrypt_attachment!(round: 111, armored: "fresh")
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\n#{armored}\n-----END AGE ENCRYPTED FILE-----",
      round: round,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  it "locks a draft photo with an envelope (tlock of the key, AES of the original)" do
    photo = create(:leverage_photo, :with_images, user: user)
    stub_encrypt_bytes!

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_bytes)
    photo.reload
    expect(photo.status).to eq("active")
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    expect(photo.tlock_layer_count).to eq(1)
    expect(photo.original_image).not_to be_attached
    expect(photo.encrypted_original).to be_attached
    expect(photo.tlock_blob).to be_attached
  end

  it "re-locks a photo that was unlocked, even though its plaintext original was already purged" do
    photo = create(:leverage_photo, :unlocked, user: user)
    expect(photo.original_image).not_to be_attached
    expect(photo.tlock_blob).to be_attached
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_FULL_IMAGE)
    stub_encrypt_bytes!(round: 222, armored: "key")

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_bytes)
    photo.reload
    expect(photo.status).to eq("active")
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    expect(photo.tlock_layer_count).to eq(1)
    expect(photo.encrypted_original).to be_attached
    expect(photo.locked_until).to be_within(5.seconds).of(Time.current + duration_seconds.seconds)
  end

  it "resets the layer count when converting an unlocked full-image lock to an envelope" do
    photo = create(:leverage_photo, :unlocked, user: user, tlock_layer_count: 3)
    stub_encrypt_bytes!(round: 222, armored: "key")

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(photo.reload.tlock_layer_count).to eq(1)
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
  end

  it "starts a fresh envelope when an unlocked photo has its original back" do
    photo = create(:leverage_photo, :unlocked, user: user)
    photo.tlock_blob.purge
    photo.original_image.attach(
      io: StringIO.new("restored-original"),
      filename: "original.jpg",
      content_type: "image/jpeg"
    )
    stub_encrypt_bytes!

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_bytes)
    photo.reload
    expect(photo.tlock_layer_count).to eq(1)
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    expect(photo.encrypted_original).to be_attached
  end

  it "converts a full-image tlock to an envelope when a non-image original is also attached" do
    photo = create(:leverage_photo, :unlocked, user: user)
    photo.original_image.attach(
      io: StringIO.new('{"v":1,"photo_id":1,"alg":"aes-256-gcm","k":"x"}'),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    stub_encrypt_bytes!(round: 333, armored: "key")
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment)

    described_class.new(photo: photo, duration_seconds: duration_seconds).call!

    expect(LeveragePhotos::TlockCrypto).to have_received(:encrypt_bytes)
    expect(LeveragePhotos::TlockCrypto).not_to have_received(:encrypt_attachment)
    photo.reload
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    expect(photo.encrypted_original).to be_attached
    expect(photo.original_image).not_to be_attached
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
