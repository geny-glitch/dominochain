# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperRotations::Save do
  let(:user) { create(:user, :beta) }
  let(:device) { create(:device, user: user) }

  before do
    allow(FcmService).to receive(:send_background_changed_notifications)
  end

  def wallpaper_with_image
    wallpaper = create(:wallpaper, device: device)
    wallpaper.image.attach(io: StringIO.new("img"), filename: "a.jpg", content_type: "image/jpeg")
    wallpaper
  end

  it "stores an enabled playlist and notifies the phone" do
    first = wallpaper_with_image
    second = wallpaper_with_image

    playlist = described_class.new(
      device: device,
      enabled: true,
      interval_seconds: 45,
      collages_enabled: true,
      wallpaper_ids: [second.id, first.id]
    ).call

    expect(playlist).to be_active
    expect(playlist.interval_seconds).to eq(45)
    expect(playlist.ordered_wallpapers.map(&:id)).to eq([second.id, first.id])
    expect(FcmService).to have_received(:send_background_changed_notifications).with(device: device)
  end

  it "refuses to start with one photo" do
    one = wallpaper_with_image

    expect {
      described_class.new(
        device: device,
        enabled: true,
        interval_seconds: 30,
        collages_enabled: true,
        wallpaper_ids: [one.id]
      ).call
    }.to raise_error(described_class::NeedTwoPhotos)
  end

  it "refuses intervals under 10 seconds" do
    first = wallpaper_with_image
    second = wallpaper_with_image

    expect {
      described_class.new(
        device: device,
        enabled: true,
        interval_seconds: 5,
        collages_enabled: false,
        wallpaper_ids: [first.id, second.id]
      ).call
    }.to raise_error(described_class::InvalidInterval)
  end
end
