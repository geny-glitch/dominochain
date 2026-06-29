# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperScreenshotComparator do
  let(:device) { create(:device, screen_width: 540, screen_height: 960) }
  let(:wallpaper) { create(:wallpaper, device: device) }
  let(:screenshot) { create(:device_screenshot, device: device) }

  before do
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
  end

  def compare
    described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device).compare
  end

  it "marks identical images as verified" do
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )

    result = compare

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.9
  end

  it "marks clearly different images as mismatch" do
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
    WallpaperVerificationTestImages.attach_pattern_png(
      screenshot,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color_a: [0, 0, 0],
      color_b: [255, 255, 255]
    )

    result = compare

    expect(result.status).to eq("mismatch")
    expect(result.score).to be <= 0.5
  end

  it "keeps a heavily overlaid screenshot verified via fuzzy matching" do
    WallpaperVerificationTestImages.attach_overlay_screenshot(
      screenshot,
      base_color: [120, 80, 200],
      overlay_color: [20, 20, 20]
    )

    result = compare

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.65
  end
end
