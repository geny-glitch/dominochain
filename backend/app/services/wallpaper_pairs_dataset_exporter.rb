# frozen_string_literal: true

class WallpaperPairsDatasetExporter
  LOCAL_MATCH_ALGORITHM = "local_match"
  DEFAULT_ROOT = Rails.root.join("wallpaper_pairs")

  ExportResult = Struct.new(:path, :screenshot_id, :expected_status, keyword_init: true)

  def initialize(root: DEFAULT_ROOT)
    @root = Pathname.new(root)
  end

  def export_disagreements!(reviews: nil, overwrite: false)
    reviews ||= WallpaperPairReview.disagreeing_with_local_match.includes(
      :reviewed_by,
      device_screenshot: { image_attachment: :blob },
      wallpaper: { image_attachment: :blob }
    )

    reviews.filter_map do |review|
      export_review!(review, overwrite: overwrite)
    end
  end

  def export_review!(review, overwrite: false)
    screenshot = review.device_screenshot
    wallpaper = review.wallpaper
    return nil unless screenshot&.image&.attached? && wallpaper&.image&.attached?

    comparison = screenshot.wallpaper_algorithm_comparisons.find { |row| row.algorithm == LOCAL_MATCH_ALGORITHM }
    comparison ||= WallpaperAlgorithmComparison.find_by(
      device_screenshot_id: screenshot.id,
      algorithm: LOCAL_MATCH_ALGORITHM
    )
    return nil unless comparison
    return nil if review.expected_status == comparison.status

    out_dir = @root.join(review.expected_status, "screenshot_#{screenshot.id}")
    return nil if out_dir.directory? && !overwrite

    out_dir.mkpath

    reference_file = write_attachment(wallpaper.image, out_dir, basename: "reference")
    screenshot_file = write_attachment(screenshot.image, out_dir, basename: "screenshot")

    manifest = build_manifest(review: review, screenshot: screenshot, wallpaper: wallpaper, comparison: comparison)
    manifest["files"] = { "reference" => reference_file, "screenshot" => screenshot_file }

    (out_dir + "manifest.json").write(JSON.pretty_generate(manifest))

    ExportResult.new(
      path: out_dir,
      screenshot_id: screenshot.id,
      expected_status: review.expected_status
    )
  end

  private

  def build_manifest(review:, screenshot:, wallpaper:, comparison:)
    device = screenshot.device
    user = device&.user

    {
      source: ENV.fetch("FLY_APP", "local"),
      exported_at: Time.current.iso8601,
      user_nickname: user&.nickname,
      device_id: device&.id,
      device_screen_width: device&.screen_width,
      device_screen_height: device&.screen_height,
      device_screenshot_id: screenshot.id,
      wallpaper_id: wallpaper.id,
      captured_at: screenshot.captured_at&.iso8601,
      staging_verification_status: screenshot.verification_status,
      staging_similarity_score: screenshot.similarity_score,
      expected_verification_status: review.expected_status,
      reviewed_at: review.reviewed_at&.iso8601,
      reviewed_by_nickname: review.reviewed_by&.nickname,
      local_match_status: comparison.status,
      local_match_score: comparison.score,
      local_match_strong_match_count: comparison.strong_match_count,
      local_match_peak_score: comparison.peak_score,
      disagreement: {
        admin_status: review.expected_status,
        local_match_status: comparison.status
      }
    }
  end

  def write_attachment(attachment, out_dir, basename:)
    extension = extension_for_content_type(attachment.content_type)
    filename = "#{basename}#{extension}"
    File.binwrite(out_dir + filename, attachment.download)
    filename
  end

  def extension_for_content_type(content_type)
    content_type == "image/jpeg" ? ".jpg" : ".png"
  end
end
