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

  it "defaults tlock_format to full_image so existing locks keep peeling the whole blob" do
    photo = create(:leverage_photo, :unlocked, user: user)
    expect(photo.tlock_format).to eq(described_class::TLOCK_FORMAT_FULL_IMAGE)
    expect(photo).to be_full_image_lock
    expect(photo).to be_needs_legacy_client_peel
  end

  it "allows re-locking after unlock" do
    photo = create(:leverage_photo, :unlocked, user: user)
    expect(photo).to be_ready_to_relock
    expect(photo).to be_can_start_timer
    expect(photo).not_to be_eligible_for_start
  end

  it "allows draft with only a preview censored version" do
    photo = create(:leverage_photo, :without_censor, user: user)
    expect(photo).not_to be_needs_censor
    expect(photo.censored_images.count).to eq(1)
    expect(photo).to be_ready_to_lock
    expect(photo).to be_can_censor
    expect(photo).to be_can_attach_censored
  end

  it "sorts photos by unlock date with drafts last" do
    later = create(:leverage_photo, :active, user: user, locked_until: 3.days.from_now)
    sooner = create(:leverage_photo, :active, user: user, locked_until: 1.hour.from_now)
    draft = create(:leverage_photo, :with_images, user: user)

    ids = described_class.for_user_list(user, sort: "unlock_asc").map(&:id)
    expect(ids).to eq([sooner.id, later.id, draft.id])

    ids = described_class.for_user_list(user, sort: "unlock_desc").map(&:id)
    expect(ids).to eq([later.id, sooner.id, draft.id])
  end

  it "sanctions by deleting original only" do
    photo = create(:leverage_photo, :with_images, user: user)
    expect(photo.censored_images.count).to eq(2)
    photo.delete_original_from_sanction!
    photo.reload
    expect(photo).to be_sanctioned
    expect(photo.original_image).not_to be_attached
    expect(photo.censored_images.count).to eq(2)
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

  it "does not treat an envelope key payload as a restored original" do
    photo = create(:leverage_photo, :unlocked, user: user)
    photo.encrypted_original.attach(
      io: StringIO.new("aes-bytes"),
      filename: "original.bin",
      content_type: "application/octet-stream"
    )
    key = {
      v: 1,
      photo_id: photo.id,
      alg: "aes-256-gcm",
      k: "abc",
      ciphertext_sha256: "d" * 64
    }.to_json
    file = Rack::Test::UploadedFile.new(
      StringIO.new(key),
      "image/jpeg",
      true,
      original_filename: "photo.jpg"
    )

    expect { photo.persist_restored_original!(file) }.to raise_error(ArgumentError, /not an image/)
    expect(photo.reload.encrypted_original).to be_attached
    expect(photo.tlock_blob).to be_attached
    expect(photo).not_to be_viewable_original
  end

  it "can_delete_original? requires at least one censored version" do
    photo = create(:leverage_photo, :without_censor, user: user)
    expect(photo).to be_can_delete_original

    photo = create(:leverage_photo, :with_images, user: user)
    expect(photo).to be_can_delete_original
  end

  it "permanently deletes attachments and marks deleted" do
    photo = create(:leverage_photo, :with_images, user: user, original_filename: "keep.jpg")
    photo.permanently_delete!
    expect(photo).to be_deleted
    expect(photo.original_filename).to be_nil
    expect(photo.original_image).not_to be_attached
    expect(photo.censored_images).not_to be_attached
  end

  it "summarizes the current lock duration and extensions" do
    photo = create(:leverage_photo, :active, user: user, initial_duration_seconds: 1.day.to_i)
    photo.leverage_photo_extensions.create!(
      added_seconds: 3600,
      locked_until_before: photo.locked_until,
      locked_until_after: photo.locked_until + 1.hour,
      drand_round_added: 99_001
    )
    photo.leverage_photo_extensions.create!(
      added_seconds: 1800,
      locked_until_before: photo.locked_until + 1.hour,
      locked_until_after: photo.locked_until + 90.minutes,
      drand_round_added: 99_002
    )

    entries = photo.current_lock_time_entries
    expect(entries.map { |row| row[:kind] }).to eq(%i[started added added])
    expect(entries.map { |row| row[:seconds] }).to eq([86_400, 3600, 1800])
    expect(photo.current_lock_total_seconds).to eq(91_800)
  end

  it "tracks an explicit add-time base and multiplier" do
    photo = create(:leverage_photo, :active, user: user)
    expect(photo.add_time_base?).to be(false)
    expect(photo.next_step_n).to eq(1)

    photo.update!(add_time_base_seconds: 3.days.to_i, add_time_step_n: 1)
    expect(photo.add_time_base?).to be(true)
    expect(photo.next_step_n).to eq(2)
    expect(photo.next_step_seconds).to eq(6.days.to_i)

    photo.update!(add_time_step_n: 2)
    expect(photo.next_step_seconds).to eq(9.days.to_i)
  end

  it "splits durations into the largest exact unit" do
    expect(described_class.duration_parts(3.days.to_i)).to eq([3, "days"])
    expect(described_class.duration_parts(7.days.to_i)).to eq([1, "weeks"])
    expect(described_class.duration_parts(2.hours.to_i)).to eq([2, "hours"])
    expect(described_class.duration_parts(90.minutes.to_i)).to eq([90, "minutes"])
  end

  it "picks the largest censored blob as the preferred preview" do
    photo = create(:leverage_photo, :with_images, user: user)
    expect(photo.preferred_censored_attachment.filename.to_s).to eq("censored.jpg")
    expect(photo.thumbnail_attachment.filename.to_s).to eq("teaser.jpg")
  end
end
