# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::RestorePayload do
  let(:user) { create(:user, :beta) }

  it "peels a full-image lock on the server" do
    photo = create(:leverage_photo, :unlocked, user: user)
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment).and_return("fake-original")

    described_class.call!(photo)

    expect(photo.reload.original_image.download).to eq("fake-original")
    expect(photo.tlock_blob).not_to be_attached
  end

  it "is a no-op when the original is already viewable" do
    photo = create(:leverage_photo, :with_images, user: user)
    allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment)

    described_class.call!(photo)

    expect(LeveragePhotos::TlockCrypto).not_to have_received(:decrypt_attachment)
  end
end
