# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperPairsDatasetExporter do
  include ActiveJob::TestHelper
  let(:admin) { create(:user, :admin) }
  let(:device) { create(:device) }
  let(:wallpaper) { create(:wallpaper, device: device) }
  let(:screenshot) { create(:device_screenshot, device: device, wallpaper: wallpaper) }
  let(:export_root) { Rails.root.join("tmp/wallpaper_pairs_export_spec") }
  let(:exporter) { described_class.new(root: export_root) }

  before do
    FileUtils.rm_rf(export_root)
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: 540,
      height: 960,
      color: [120, 80, 200]
    )
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: 540,
      height: 960,
      color: [40, 40, 40]
    )
    perform_enqueued_jobs
  end

  after do
    FileUtils.rm_rf(export_root)
  end

  it "exports pairs where admin review disagrees with local_match" do
    review = WallpaperPairReview.create!(
      device_screenshot: screenshot,
      wallpaper: wallpaper,
      reviewed_by: admin,
      reviewed_at: Time.current,
      expected_status: "verified"
    )
    WallpaperAlgorithmComparison.create!(
      device_screenshot: screenshot,
      algorithm: "local_match",
      status: "mismatch",
      score: 0.21,
      strong_match_count: 1,
      peak_score: 0.4,
      compared_at: Time.current
    )

    results = exporter.export_disagreements!

    expect(results.size).to eq(1)
    out_dir = export_root.join("verified", "screenshot_#{screenshot.id}")
    expect(out_dir).to be_directory
    manifest = JSON.parse((out_dir + "manifest.json").read)
    expect(manifest.fetch("expected_verification_status")).to eq("verified")
    expect(manifest.fetch("local_match_status")).to eq("mismatch")
    expect(manifest.fetch("disagreement")).to eq(
      "admin_status" => "verified",
      "local_match_status" => "mismatch"
    )
    expect((out_dir + manifest.fetch("files").fetch("reference")).exist?).to be(true)
    expect((out_dir + manifest.fetch("files").fetch("screenshot")).exist?).to be(true)
  end

  it "skips pairs that agree with local_match" do
    WallpaperPairReview.create!(
      device_screenshot: screenshot,
      wallpaper: wallpaper,
      reviewed_by: admin,
      reviewed_at: Time.current,
      expected_status: "verified"
    )
    WallpaperAlgorithmComparison.create!(
      device_screenshot: screenshot,
      algorithm: "local_match",
      status: "verified",
      score: 0.91,
      compared_at: Time.current
    )

    results = exporter.export_disagreements!

    expect(results).to be_empty
    expect(export_root).not_to exist
  end
end
