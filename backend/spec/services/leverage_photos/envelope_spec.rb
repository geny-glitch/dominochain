# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::Envelope do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }

  def stub_encrypt_bytes!(captured)
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes) do |bytes, _locked_until|
      captured[:payload] = bytes
      {
        armored: "-----BEGIN AGE ENCRYPTED FILE-----\nkey\n-----END AGE ENCRYPTED FILE-----",
        round: 42_001,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      }
    end
  end

  def unlock_without_original!(payload)
    photo.tlock_blob.attach(
      io: StringIO.new("AGE-KEY"),
      filename: "layer.tlock",
      content_type: "text/plain"
    )
    photo.original_image.purge
    photo.update!(status: "unlocked", tlock_format: LeveragePhoto::TLOCK_FORMAT_ENVELOPE)
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment).and_return(payload)
  end

  it "seals the original with AES-GCM and tlock-encrypts a bound key payload" do
    captured = {}
    stub_encrypt_bytes!(captured)

    result = described_class.seal!(photo, 1.hour.from_now)

    expect(result[:round]).to eq(42_001)
    expect(photo.encrypted_original).to be_attached
    payload = JSON.parse(captured[:payload])
    expect(payload["v"]).to eq(1)
    expect(payload["photo_id"]).to eq(photo.id)
    expect(payload["alg"]).to eq("aes-256-gcm")
    expect(payload["k"]).to be_present
    expect(payload["ciphertext_sha256"]).to match(/\A[0-9a-f]{64}\z/)
    expect(Digest::SHA256.hexdigest(photo.encrypted_original.download)).to eq(payload["ciphertext_sha256"])
  end

  it "seals an existing full-image tlock onion as the envelope ciphertext" do
    photo.original_image.purge
    photo.tlock_blob.attach(
      io: StringIO.new("-----BEGIN AGE ENCRYPTED FILE-----\nlegacy\n-----END AGE ENCRYPTED FILE-----"),
      filename: "layer.tlock",
      content_type: "text/plain"
    )
    captured = {}
    stub_encrypt_bytes!(captured)

    packed, crypto = described_class.new(photo).wrap_existing_blob(1.hour.from_now)

    expect(crypto[:round]).to eq(42_001)
    expect(packed.bytesize).to be > 16
    payload = JSON.parse(captured[:payload])
    expect(payload["photo_id"]).to eq(photo.id)
    expect(Digest::SHA256.hexdigest(packed)).to eq(payload["ciphertext_sha256"])
  end

  it "restores the original after peeling the envelope key" do
    captured = {}
    stub_encrypt_bytes!(captured)
    described_class.seal!(photo, 1.hour.from_now)
    original_bytes = "fake-original"
    unlock_without_original!(captured[:payload])

    described_class.open!(photo)

    photo.reload
    expect(photo.original_image.download).to eq(original_bytes)
    expect(photo.tlock_blob).not_to be_attached
    expect(photo.encrypted_original).not_to be_attached
  end

  it "rejects a swapped ciphertext even if the key peels" do
    captured = {}
    stub_encrypt_bytes!(captured)
    described_class.seal!(photo, 1.hour.from_now)
    photo.encrypted_original.purge
    photo.encrypted_original.attach(
      io: StringIO.new("not-the-original-ciphertext"),
      filename: "original.bin",
      content_type: "application/octet-stream"
    )
    unlock_without_original!(captured[:payload])

    expect { described_class.open!(photo) }.to raise_error(described_class::Error, /mismatch/)
  end

  it "server-peels a converted full-image onion after opening the envelope" do
    onion = "-----BEGIN AGE ENCRYPTED FILE-----\nlegacy\n-----END AGE ENCRYPTED FILE-----"
    photo.original_image.purge
    photo.tlock_blob.attach(
      io: StringIO.new(onion),
      filename: "layer.tlock",
      content_type: "text/plain"
    )
    captured = {}
    stub_encrypt_bytes!(captured)
    packed, = described_class.new(photo).wrap_existing_blob(1.hour.from_now)
    photo.encrypted_original.attach(
      io: StringIO.new(packed),
      filename: "original.bin",
      content_type: "application/octet-stream"
    )
    unlock_without_original!(captured[:payload])
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_bytes).and_return("fake-original")

    described_class.open!(photo)

    expect(LeveragePhotos::TlockCrypto).to have_received(:decrypt_bytes)
    photo.reload
    expect(photo.original_image.download).to eq("fake-original")
    expect(photo.tlock_blob).not_to be_attached
    expect(photo.encrypted_original).not_to be_attached
  end
end
