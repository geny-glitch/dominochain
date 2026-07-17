# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::ResolveTarget do
  let(:user) { create(:user, :beta) }

  it "returns a specific eligible draft for start" do
    draft = create(:leverage_photo, :with_images, user: user, original_filename: "a.jpg")
    create(:leverage_photo, :active, user: user, original_filename: "b.jpg")

    photo = described_class.call(
      user: user,
      action: :start,
      target_mode: "specific",
      photo_id: draft.id
    )
    expect(photo).to eq(draft)
  end

  it "returns nil when specific photo is ineligible" do
    active = create(:leverage_photo, :active, user: user)

    photo = described_class.call(
      user: user,
      action: :start,
      target_mode: "specific",
      photo_id: active.id
    )
    expect(photo).to be_nil
  end

  it "samples from eligible active photos for add_time" do
    active = create(:leverage_photo, :active, user: user)
    create(:leverage_photo, :with_images, user: user)

    photo = described_class.call(
      user: user,
      action: :add_time,
      target_mode: "random"
    )
    expect(photo).to eq(active)
  end

  it "prefers active photos when randomly resolving lock" do
    active = create(:leverage_photo, :active, user: user)
    create(:leverage_photo, :with_images, user: user)

    photo = described_class.call(
      user: user,
      action: :lock,
      target_mode: "random"
    )
    expect(photo).to eq(active)
  end

  it "returns a draft when lock random pool has no active photo" do
    draft = create(:leverage_photo, :with_images, user: user)

    photo = described_class.call(
      user: user,
      action: :lock,
      target_mode: "random"
    )
    expect(photo).to eq(draft)
  end

  it "accepts specific lock targets that can start or extend" do
    draft = create(:leverage_photo, :with_images, user: user)
    active = create(:leverage_photo, :active, user: user)

    expect(
      described_class.call(user: user, action: :lock, target_mode: "specific", photo_id: draft.id)
    ).to eq(draft)
    expect(
      described_class.call(user: user, action: :lock, target_mode: "specific", photo_id: active.id)
    ).to eq(active)
  end

  it "returns nil when random pool is empty" do
    photo = described_class.call(
      user: user,
      action: :delete,
      target_mode: "random"
    )
    expect(photo).to be_nil
  end
end
