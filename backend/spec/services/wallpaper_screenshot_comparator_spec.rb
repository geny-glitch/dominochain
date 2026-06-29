# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperScreenshotComparator do
  include ActiveJob::TestHelper

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

  def attach_matching_screenshot
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
    perform_enqueued_jobs
  end

  it "marks identical images as verified" do
    attach_matching_screenshot

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
    perform_enqueued_jobs

    result = compare

    expect(result.status).to eq("mismatch")
    expect(result.score).to be <= 0.55
  end

  it "keeps a heavily overlaid screenshot verified via fuzzy matching" do
    WallpaperVerificationTestImages.attach_overlay_screenshot(
      screenshot,
      base_color: [120, 80, 200],
      overlay_color: [20, 20, 20]
    )
    perform_enqueued_jobs

    result = compare

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.65
  end

  it "marks a lock screen screenshot with heavy system overlays as verified" do
    device = create(:device, screen_width: 1170, screen_height: 2532)
    wallpaper = create(:wallpaper, device: device)
    screenshot = create(:device_screenshot, device: device)

    WallpaperVerificationTestImages.attach_fixture(
      wallpaper,
      attachment_name: :image,
      filename: "wallpaper_reference.png"
    )
    WallpaperVerificationTestImages.attach_fixture(
      screenshot,
      attachment_name: :image,
      filename: "wallpaper_lock_screen_screenshot.png"
    )
    perform_enqueued_jobs

    result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device).compare

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.48
    expect(result.score).to be <= 0.65
  end

  it "requires processed boss_preview variants" do
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )

    expect { compare }.to raise_error(ImagePreviewVariant::PreviewNotReady)
  end

  context "with a wallpaper sample" do
    let(:sample) { create(:device_wallpaper_sample, device: device) }

    def compare_sample
      described_class.new(sample: sample, wallpaper: wallpaper, device: device).compare
    end

    def attach_matching_sample
      WallpaperVerificationTestImages.attach_png(
        sample,
        attachment_name: :image,
        width: device.screen_width,
        height: device.screen_height,
        color: [120, 80, 200]
      )
      perform_enqueued_jobs
    end

    it "marks identical wallpaper samples as verified without screenshot heuristics" do
      attach_matching_sample

      result = compare_sample

      expect(result.status).to eq("verified")
      expect(result.score).to be >= 0.9
    end

    it "marks clearly different wallpaper samples as mismatch" do
      WallpaperVerificationTestImages.attach_pattern_png(
        sample,
        attachment_name: :image,
        width: device.screen_width,
        height: device.screen_height,
        color_a: [0, 0, 0],
        color_b: [255, 255, 255]
      )
      perform_enqueued_jobs

      result = compare_sample

      expect(result.status).to eq("mismatch")
      expect(result.score).to be <= 0.55
    end
  end
end
