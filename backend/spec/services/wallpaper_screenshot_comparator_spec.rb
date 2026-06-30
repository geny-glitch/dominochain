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

  it "verifies nominal lock-screen metrics with elevated dHash and MAD from system chrome" do
    result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device)
      .send(:classify, ssim: 0.4, dhash_distance: 38, mad: 42)

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.52
    expect(result.score).to be <= 0.56
  end

  it "verifies overlay-band scores even when MAD exceeds the old strict overlay cap" do
    result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device)
      .send(:classify, ssim: 0.38, dhash_distance: 36, mad: 48)

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.48
    expect(result.score).to be <= 0.56
  end

  def compare_wallpaper_pair(pair_name)
    manifest = JSON.parse(Rails.root.join("spec/fixtures/files/wallpaper_pairs/#{pair_name}/manifest.json").read)
    files = manifest.fetch("files")
    pair_device = create(
      :device,
      screen_width: manifest.fetch("device_screen_width"),
      screen_height: manifest.fetch("device_screen_height")
    )
    pair_wallpaper = create(:wallpaper, device: pair_device)
    pair_screenshot = create(:device_screenshot, device: pair_device)

    WallpaperVerificationTestImages.attach_fixture(
      pair_wallpaper,
      attachment_name: :image,
      filename: "wallpaper_pairs/#{pair_name}/#{files.fetch('reference')}"
    )
    WallpaperVerificationTestImages.attach_fixture(
      pair_screenshot,
      attachment_name: :image,
      filename: "wallpaper_pairs/#{pair_name}/#{files.fetch('screenshot')}"
    )
    perform_enqueued_jobs

    result = described_class.new(
      screenshot: pair_screenshot,
      wallpaper: pair_wallpaper,
      device: pair_device
    ).compare

    [result, manifest]
  end

  it "verifies the staging nominal wallpaper pair" do
    result, _manifest = compare_wallpaper_pair("nominal")

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.48
  end

  it "verifies the staging nominal2 wallpaper pair" do
    result, manifest = compare_wallpaper_pair("nominal2")

    expect(result.status).to eq(manifest.fetch("staging_verification_status"))
    expect(result.score).to be >= 0.48
  end

  it "marks the staging mismatch wallpaper pair as mismatch" do
    result, _manifest = compare_wallpaper_pair("mismatch")

    expect(result.status).to eq("mismatch")
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
end
