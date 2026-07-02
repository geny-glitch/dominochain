# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperAlgorithmComparisonRunner do
  include ActiveJob::TestHelper

  let(:device) { create(:device, screen_width: 540, screen_height: 960) }
  let(:wallpaper) { create(:wallpaper, device: device) }
  let(:screenshot) { create(:device_screenshot, device: device, wallpaper: wallpaper) }

  before do
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
    perform_enqueued_jobs
  end

  it "stores a comparison result for the requested algorithm" do
    comparison = described_class.new(screenshot: screenshot, algorithm: "local_match").run!

    expect(comparison).to be_persisted
    expect(comparison.algorithm).to eq("local_match")
    expect(comparison.status).to eq("verified")
    expect(comparison.score).to be >= 0.85
    expect(comparison.compared_at).to be_present
  end

  it "upserts when rerun" do
    described_class.new(screenshot: screenshot, algorithm: "grid_fuzzy").run!
    first = WallpaperAlgorithmComparison.find_by!(device_screenshot: screenshot, algorithm: "grid_fuzzy")
    first_compared_at = first.compared_at

    travel 1.minute do
      described_class.new(screenshot: screenshot, algorithm: "grid_fuzzy").run!
    end

    expect(WallpaperAlgorithmComparison.where(device_screenshot: screenshot, algorithm: "grid_fuzzy").count).to eq(1)
    expect(first.reload.compared_at).to be > first_compared_at
  end

  it "rejects unknown algorithms" do
    expect {
      described_class.new(screenshot: screenshot, algorithm: "unknown").run!
    }.to raise_error(ArgumentError, /Unknown algorithm/)
  end
end
