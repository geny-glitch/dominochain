# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::ApplyAsWallpaper do
  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }

  before do
    allow(FcmService).to receive(:send_background_changed_notifications_to_devices)
    allow(WallpaperEnforcementEvaluator).to receive(:new).and_return(
      instance_double(WallpaperEnforcementEvaluator, reset_mismatch_on_wallpaper_change!: true)
    )
  end

  it "applies the original as wallpaper on all devices and stashes it" do
    described_class.new(photo: photo, user: user).call!

    wallpaper = device.reload.current_wallpaper
    expect(wallpaper).to be_present
    expect(wallpaper.leverage_photo_id).to eq(photo.id)
    expect(wallpaper.image.download).to eq("fake-original")
    expect(wallpaper.leverage_original_image).to be_attached
    expect(wallpaper.leverage_original_image.download).to eq("fake-original")
  end

  it "uses censored image when the photo is already locked" do
    photo = create(:leverage_photo, :active, user: user)

    described_class.new(photo: photo, user: user).call!

    wallpaper = device.reload.current_wallpaper
    expect(wallpaper.image.download).to eq("fake-censored")
    expect(wallpaper.leverage_original_image).not_to be_attached
  end

  it "uses the teaser when variant is teaser" do
    described_class.new(photo: photo, user: user, variant: :teaser).call!

    wallpaper = device.reload.current_wallpaper
    expect(wallpaper.image.download).to eq("fake-teaser")
  end

  it "uses the censored image when variant is censored" do
    photo = create(:leverage_photo, :active, user: user)

    described_class.new(photo: photo, user: user, variant: :censored).call!

    wallpaper = device.reload.current_wallpaper
    expect(wallpaper.image.download).to eq("fake-censored")
  end

  it "raises when the user has no device" do
    device.destroy!
    expect {
      described_class.new(photo: photo, user: user.reload).call!
    }.to raise_error(described_class::Error, "no device")
  end
end
