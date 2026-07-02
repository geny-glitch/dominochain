# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperScreenshotComparator do
  include ActiveJob::TestHelper

  REGRESSION_ROOT = Rails.root.join("spec/fixtures/files/wallpaper_pairs")
  REGRESSION_STATUSES = %w[verified mismatch].freeze

  def regression_manifest_paths
    WallpaperPairsRegressionPaths.manifest_paths(statuses: REGRESSION_STATUSES)
  end

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

  def compare_from_manifest(manifest_path, algorithm: "grid_fuzzy")
    manifest_path = Pathname.new(manifest_path)
    manifest = JSON.parse(manifest_path.read)
    files = manifest.fetch("files")
    fixture_dir = manifest_path.dirname
    pair_device = create(
      :device,
      screen_width: manifest.fetch("device_screen_width"),
      screen_height: manifest.fetch("device_screen_height")
    )
    pair_wallpaper = create(:wallpaper, device: pair_device)
    pair_screenshot = create(:device_screenshot, device: pair_device)

    WallpaperVerificationTestImages.attach_from_path(
      pair_wallpaper,
      attachment_name: :image,
      path: fixture_dir.join(files.fetch("reference"))
    )
    WallpaperVerificationTestImages.attach_from_path(
      pair_screenshot,
      attachment_name: :image,
      path: fixture_dir.join(files.fetch("screenshot"))
    )
    perform_enqueued_jobs

    result = described_class.new(
      screenshot: pair_screenshot,
      wallpaper: pair_wallpaper,
      device: pair_device,
      algorithm: algorithm
    ).compare

    [result, manifest]
  end

  it "marks identical images as verified" do
    attach_matching_screenshot

    result = compare

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.9
    expect(result.cells_compared).to be_positive
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
      .send(:classify_grid_fuzzy, ssim: 0.4, dhash_distance: 38, mad: 42)

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.52
    expect(result.score).to be <= 0.56
  end

  it "verifies overlay-band scores even when MAD exceeds the old strict overlay cap" do
    result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device)
      .send(:classify_grid_fuzzy, ssim: 0.38, dhash_distance: 36, mad: 48)

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.48
    expect(result.score).to be <= 0.56
  end

  it "marks ambiguous comparisons below the verified bar as mismatch" do
    result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device)
      .send(:classify_grid_fuzzy, ssim: 0.05, dhash_distance: 30, mad: 44)

    expect(result.status).to eq("mismatch")
    expect(result.score).to be < 0.48
  end

  REGRESSION_STATUSES.each do |expected_status|
    regression_manifest_paths
      .select { |manifest_path| manifest_path.include?("/#{expected_status}/") }
      .each do |manifest_path|
      pair_label = File.basename(File.dirname(manifest_path))

      it "classifies regression fixture #{expected_status}/#{pair_label} as #{expected_status} (grid_fuzzy)" do
        result, manifest = compare_from_manifest(manifest_path, algorithm: "grid_fuzzy")

        expect(result.status).to eq(manifest.fetch("expected_verification_status", expected_status))
        if expected_status == "verified"
          expect(result.score).to be >= 0.48
        end
      end
    end
  end

  describe "labeled regression fixtures (local_match)" do
    regression_fixtures = regression_manifest_paths.map do |manifest_path|
      expected_status = REGRESSION_STATUSES.find { |status| manifest_path.include?("/#{status}/") }
      [expected_status, File.basename(File.dirname(manifest_path)), manifest_path]
    end

    if regression_fixtures.empty?
      it "runs when fixtures are present (fetch with bin/fetch-wallpaper-regression-dataset)" do
        skip "No labeled regression fixtures under spec/fixtures/files/wallpaper_pairs or wallpaper_pairs/"
      end
    else
      if ENV["DUMP_WALLPAPER_REGRESSION"] == "1"
        it "dumps local_match metrics for all labeled pairs" do
          regression_fixtures.each do |expected_status, pair_label, manifest_path|
            result, = compare_from_manifest(manifest_path, algorithm: "local_match")
            ok = result.status == expected_status ? "OK" : "FAIL"
            warn format(
              "%s %s/%s status=%s score=%.3f strong=%s ratio=%.3f peak=%.3f cells=%s",
              ok, expected_status, pair_label, result.status, result.score,
              result.strong_match_count, result.strong_match_ratio.to_f, result.peak_score.to_f,
              result.cells_compared
            )
          end
        end
      end

      regression_fixtures.each do |expected_status, pair_label, manifest_path|
        it "classifies regression fixture #{expected_status}/#{pair_label} as #{expected_status} (local_match)" do
          result, manifest = compare_from_manifest(manifest_path, algorithm: "local_match")

          expect(result.algorithm).to eq("local_match")
          expect(result.status).to eq(manifest.fetch("expected_verification_status", expected_status))
        end
      end
    end
  end

  it "compares previews with different boss_preview dimensions without error" do
    device = create(:device, screen_width: 1344, screen_height: 2769)
    wallpaper = create(:wallpaper, device: device)
    screenshot = create(:device_screenshot, device: device)

    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: 248,
      height: 512,
      color: [120, 80, 200]
    )
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: 287,
      height: 640,
      color: [120, 80, 200]
    )
    perform_enqueued_jobs

    result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device).compare

    expect(result.status).to eq("verified")
    expect(result.score).to be >= 0.9
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

  describe "local_match algorithm" do
    def compare_local
      described_class.new(
        screenshot: screenshot,
        wallpaper: wallpaper,
        device: device,
        algorithm: "local_match"
      ).compare
    end

    it "marks identical images as verified via strong patch matches" do
      attach_matching_screenshot

      result = compare_local

      expect(result.status).to eq("verified")
      expect(result.algorithm).to eq("local_match")
      expect(result.strong_match_count).to be >= 2
      expect(result.peak_score).to be >= 0.85
    end

    it "marks clearly different images as mismatch when no patches match" do
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

      result = compare_local

      expect(result.status).to eq("mismatch")
      expect(result.strong_match_count).to eq(0)
    end

    it "keeps a heavily overlaid screenshot verified when unobstructed patches match" do
      WallpaperVerificationTestImages.attach_overlay_screenshot(
        screenshot,
        base_color: [120, 80, 200],
        overlay_color: [20, 20, 20]
      )
      perform_enqueued_jobs

      result = compare_local

      expect(result.status).to eq("verified")
      expect(result.strong_match_count).to be >= 1
    end

    it "verifies when enough strict patches match even if global metrics are weak" do
      result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device, algorithm: "local_match")
        .send(
          :classify_local_match,
          ssim: 0.4,
          dhash_distance: 38,
          mad: 42,
          score: 0.55,
          cells_compared: 40,
          cells_skipped: 20,
          strong_match_count: 5,
          strong_match_ratio: 0.125,
          peak_score: 0.91,
          p90_score: 0.62
        )

      expect(result.status).to eq("verified")
    end

    it "marks mismatch when no strict patches match" do
      result = described_class.new(screenshot: screenshot, wallpaper: wallpaper, device: device, algorithm: "local_match")
        .send(
          :classify_local_match,
          ssim: 0.2,
          dhash_distance: 30,
          mad: 44,
          score: 0.35,
          cells_compared: 40,
          cells_skipped: 20,
          strong_match_count: 0,
          strong_match_ratio: 0.0,
          peak_score: 0.45,
          p90_score: 0.32
        )

      expect(result.status).to eq("mismatch")
    end
  end
end
