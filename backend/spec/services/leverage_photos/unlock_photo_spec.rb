# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::UnlockPhoto do
  let(:user) { create(:user, :beta) }

  it "leaves a due full-image lock to client peel and does not open an envelope" do
    photo = create(:leverage_photo, :active, user: user, locked_until: 1.minute.ago)
    allow(LeveragePhotos::Envelope).to receive(:open!)

    described_class.call!(photo)

    expect(LeveragePhotos::Envelope).not_to have_received(:open!)
    photo.reload
    expect(photo).to be_unlocked
    expect(photo.tlock_blob).to be_attached
    expect(photo.original_image).not_to be_attached
    expect(photo.tlock_format).to eq(LeveragePhoto::TLOCK_FORMAT_FULL_IMAGE)
  end

  it "restores an envelope original when the timer is due" do
    photo = create(:leverage_photo, :with_images, user: user)
    captured = {}
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes) do |bytes, _|
      captured[:payload] = bytes
      { armored: "AGE-KEY", round: 11, chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH }
    end
    LeveragePhotos::StartTimerServer.new(photo: photo, duration_seconds: 3600).call!

    photo.update!(locked_until: 1.minute.ago)
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment).and_return(captured[:payload])

    described_class.call!(photo.reload)

    photo.reload
    expect(photo).to be_unlocked
    expect(photo.original_image.download).to eq("fake-original")
    expect(photo.tlock_blob).not_to be_attached
    expect(photo.encrypted_original).not_to be_attached
  end
end
