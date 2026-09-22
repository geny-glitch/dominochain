# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::UnlockPhoto do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :beta) }

  it "marks a due full-image lock unlocked and enqueues a server restore" do
    photo = create(:leverage_photo, :active, user: user, locked_until: 1.minute.ago)

    expect do
      described_class.call!(photo)
    end.to have_enqueued_job(LeveragePhotos::RestorePayloadJob).with(photo.id)

    photo.reload
    expect(photo).to be_unlocked
    expect(photo.tlock_blob).to be_attached
    expect(photo.original_image).not_to be_attached
  end

  it "restores an envelope original when the restore job runs" do
    photo = create(:leverage_photo, :with_images, user: user)
    captured = {}
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes) do |bytes, _|
      captured[:payload] = bytes
      { armored: "AGE-KEY", round: 11, chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH }
    end
    LeveragePhotos::StartTimerServer.new(photo: photo, duration_seconds: 3600).call!

    photo.update!(locked_until: 1.minute.ago)
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment).and_return(captured[:payload])

    perform_enqueued_jobs do
      described_class.call!(photo.reload)
    end

    photo.reload
    expect(photo).to be_unlocked
    expect(photo.original_image.download).to eq("fake-original")
    expect(photo.tlock_blob).not_to be_attached
    expect(photo.encrypted_original).not_to be_attached
  end

  it "server-peels a converted full-image onion when the restore job runs" do
    onion = "-----BEGIN AGE ENCRYPTED FILE-----\nlegacy\n-----END AGE ENCRYPTED FILE-----"
    photo = create(:leverage_photo, :active, user: user, locked_until: 1.hour.from_now)
    captured = {}
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes) do |bytes, _|
      captured[:payload] = bytes
      { armored: "AGE-KEY", round: 22, chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH }
    end
    photo.tlock_blob.purge
    photo.tlock_blob.attach(
      io: StringIO.new(onion),
      filename: "layer.tlock",
      content_type: "text/plain"
    )
    packed, = LeveragePhotos::Envelope.new(photo).wrap_existing_blob(2.hours.from_now)
    photo.encrypted_original.attach(
      io: StringIO.new(packed),
      filename: "original.bin",
      content_type: "application/octet-stream"
    )
    photo.tlock_blob.purge
    photo.tlock_blob.attach(
      io: StringIO.new("AGE-KEY"),
      filename: "layer.tlock",
      content_type: "text/plain"
    )
    photo.update!(
      tlock_format: LeveragePhoto::TLOCK_FORMAT_ENVELOPE,
      locked_until: 1.minute.ago
    )
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment).and_return(captured[:payload])
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_bytes).and_return("fake-original")

    perform_enqueued_jobs do
      described_class.call!(photo.reload)
    end

    photo.reload
    expect(photo).to be_unlocked
    expect(photo.original_image.download).to eq("fake-original")
    expect(photo.tlock_blob).not_to be_attached
  end
end
