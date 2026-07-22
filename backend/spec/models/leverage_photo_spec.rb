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

  it "allows re-locking after unlock" do
    photo = create(:leverage_photo, :unlocked, user: user)
    expect(photo).to be_ready_to_relock
    expect(photo).to be_can_start_timer
    expect(photo).not_to be_eligible_for_start
  end

  it "allows draft without censored reminder" do
    photo = create(:leverage_photo, :without_censor, user: user)
    expect(photo).to be_needs_censor
    expect(photo).to be_ready_to_lock
    expect(photo).to be_can_censor
  end

  it "sanctions by deleting original only" do
    photo = create(:leverage_photo, :with_images, user: user)
    photo.delete_original_from_sanction!
    photo.reload
    expect(photo).to be_sanctioned
    expect(photo.original_image).not_to be_attached
    expect(photo.censored_image).to be_attached
    expect(photo.teaser_image).to be_attached
  end

  it "persists a restored original on unlocked photos" do
    photo = create(:leverage_photo, :unlocked, user: user)
    file = Rack::Test::UploadedFile.new(
      StringIO.new("restored-bytes"),
      "image/jpeg",
      true,
      original_filename: "restored.jpg"
    )

    photo.persist_restored_original!(file)

    expect(photo.reload.original_image).to be_attached
    expect(photo.tlock_blob).not_to be_attached
    expect(photo.original_image.download).to eq("restored-bytes")
  end

  it "can_delete_original? requires censored reminder" do
    photo = create(:leverage_photo, :without_censor, user: user)
    expect(photo).not_to be_can_delete_original

    photo = create(:leverage_photo, :with_images, user: user)
    expect(photo).to be_can_delete_original
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
