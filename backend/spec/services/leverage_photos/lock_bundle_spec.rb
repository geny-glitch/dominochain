# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::LockBundle do
  let(:user) { create(:user, :beta) }

  def stub_encrypt!
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
      armored: "-----BEGIN AGE ENCRYPTED FILE-----\nAGE-KEY\n-----END AGE ENCRYPTED FILE-----",
      round: 99_001,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
    allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
      armored: "AGE-OUTER",
      round: 200_000,
      chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    )
  end

  it "locks every photo in the bundle to the same expiry" do
    first = create(:leverage_photo, :with_images, user: user, original_filename: "one.jpg")
    second = create(
      :leverage_photo,
      :with_images,
      user: user,
      original_filename: "two.jpg",
      bundle: first.bundle,
      position: 1
    )
    stub_encrypt!

    described_class.start!(photo: first, duration_seconds: 2.hours.to_i)

    first.reload
    second.reload
    expect(first).to be_active
    expect(second).to be_active
    expect(first.locked_until).to be_within(1.second).of(second.locked_until)
    expect(first.bundle_id).to eq(second.bundle_id)
  end

  it "lists a multi-photo bundle as a single vault item" do
    first = create(:leverage_photo, :with_images, user: user, original_filename: "one.jpg")
    create(
      :leverage_photo,
      :with_images,
      user: user,
      original_filename: "two.jpg",
      bundle: first.bundle,
      position: 1
    )

    covers = LeveragePhoto.for_user_list(user, sort: "newest")
    expect(covers.map(&:id)).to eq([first.id])
    expect(covers.first.bundle_mates.size).to eq(2)
  end
end
