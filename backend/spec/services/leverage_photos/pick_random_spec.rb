# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::PickRandom do
  let(:user) { create(:user, :beta) }

  it "includes locked and unlocked photos with equal eligibility" do
    draft = create(:leverage_photo, :with_images, user: user)
    active = create(:leverage_photo, :active, user: user)
    create(:leverage_photo, user: user)

    pool = described_class.new(user: user).lockable_pool

    expect(pool).to match_array([draft, active])
  end

  it "keeps the only lockable photo even when asked to exclude it" do
    photo = create(:leverage_photo, :with_images, user: user)

    picked = described_class.lockable(user: user, exclude_id: photo.id)

    expect(picked).to eq(photo)
  end

  it "excludes the current photo when another lockable photo exists" do
    first = create(:leverage_photo, :with_images, user: user)
    second = create(:leverage_photo, :active, user: user)

    picked = described_class.lockable(user: user, exclude_id: first.id)

    expect(picked).to eq(second)
  end

  it "returns any photo for the random-open action" do
    photo = create(:leverage_photo, :with_images, user: user)

    expect(described_class.any(user: user)).to eq(photo)
  end
end
