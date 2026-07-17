# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhoto, type: :model do
  let(:user) { create(:user, :beta) }

  it "allows multiple photos per user" do
    create(:leverage_photo, :with_images, user: user)
    duplicate = build(:leverage_photo, :with_images, user: user)
    expect(duplicate).to be_valid
  end

  it "normalizes original filename to jpeg stem" do
    expect(described_class.normalized_original_filename("vacation.PNG")).to eq("vacation.jpg")
    expect(described_class.normalized_original_filename("")).to eq("photo.jpg")
  end

  it "marks unlock due photos" do
    photo = create(:leverage_photo, :active, user: user, locked_until: 1.minute.ago)
    expect(photo.unlock_due?).to be(true)
    photo.mark_unlocked!
    expect(photo).to be_unlocked
  end

  it "permanently deletes attachments and marks deleted" do
    photo = create(:leverage_photo, :with_images, user: user, original_filename: "keep.jpg")
    photo.permanently_delete!
    expect(photo).to be_deleted
    expect(photo.original_filename).to be_nil
    expect(photo.original_image).not_to be_attached
    expect(photo.censored_image).not_to be_attached
    expect(photo.teaser_image).not_to be_attached
  end
end
