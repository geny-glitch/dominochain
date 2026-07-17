# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::SyncLinkedWallpapers do
  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }

  before do
    allow(FcmService).to receive(:send_background_changed_notifications_to_devices)
    allow(WallpaperEnforcementEvaluator).to receive(:new).and_return(
      instance_double(WallpaperEnforcementEvaluator, reset_mismatch_on_wallpaper_change!: true)
    )
    LeveragePhotos::ApplyAsWallpaper.new(photo: photo, user: user).call!
  end

  it "swaps current wallpaper to censored on lock and restores original on unlock" do
    wallpaper = device.reload.current_wallpaper
    expect(wallpaper.image.download).to eq("fake-original")

    LeveragePhotos::StartTimer.new(
      photo: photo,
      tlock_blob: { io: StringIO.new("AGE"), filename: "layer.tlock", content_type: "text/plain" },
      drand_round: 99_001,
      locked_until: 1.hour.from_now,
      duration_seconds: 1.hour.to_i
    ).call!

    wallpaper.reload
    expect(photo.reload).to be_active
    expect(wallpaper.image.download).to eq("fake-censored")
    expect(wallpaper.leverage_original_image.download).to eq("fake-original")

    photo.mark_unlocked!

    wallpaper.reload
    expect(photo.reload).to be_unlocked
    expect(wallpaper.image.download).to eq("fake-original")
  end

  it "falls back to teaser when censored is missing" do
    photo.censored_image.purge
    wallpaper = device.reload.current_wallpaper

    described_class.on_locking!(photo)

    expect(wallpaper.reload.image.download).to eq("fake-teaser")
  end

  it "does nothing when another wallpaper is current" do
    other = device.wallpapers.create!
    other.image.attach(io: StringIO.new("other"), filename: "other.jpg", content_type: "image/jpeg")
    device.wallpaper_applications.create!(wallpaper: other, applied_at: Time.current, applied_by: "beta_self")

    linked = Wallpaper.find_by!(leverage_photo_id: photo.id)
    original_bytes = linked.image.download

    described_class.on_locking!(photo)

    expect(linked.reload.image.download).to eq(original_bytes)
  end
end
