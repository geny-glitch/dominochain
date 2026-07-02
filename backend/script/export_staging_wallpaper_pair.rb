# frozen_string_literal: true

# Runs on the staging Rails app (via fly ssh). Prints JSON to stdout.
# Environment:
#   NICKNAME          — beta user nickname (required unless SCREENSHOT_ID is set)
#   SCREENSHOT_ID     — optional; defaults to latest screenshot for the user
#   LIST              — set to "1" to list recent screenshots instead of exporting
#   LIST_LIMIT        — optional, default 10
#   EXPORT_LABELED    — set to "1" to export all admin-labeled pairs for regression fixtures
#   EXCLUDE_IGNORED   — set to "1" to omit ignored pairs from the export

require "json"

def abort_json(message, **extra)
  warn JSON.generate({ error: message, **extra })
  exit 1
end

def presigned_url_for(blob)
  TigrisObjectStorage.presigned_download_url(blob.key, expires_in: 1.hour)
end

def screenshot_row(screenshot)
  device = screenshot.device
  user = device&.user
  wallpaper = screenshot.wallpaper_id ? Wallpaper.find_by(id: screenshot.wallpaper_id) : device&.current_wallpaper

  {
    device_screenshot_id: screenshot.id,
    user_nickname: user&.nickname,
    device_id: device&.id,
    device_screen_width: device&.screen_width,
    device_screen_height: device&.screen_height,
    captured_at: screenshot.captured_at&.iso8601,
    verification_status: screenshot.verification_status,
    similarity_score: screenshot.similarity_score,
    wallpaper_id: wallpaper&.id,
    wallpaper_attached: wallpaper&.image&.attached? == true,
    screenshot_attached: screenshot.image.attached?
  }
end

def pair_payload(screenshot, wallpaper, review: nil, comparison: nil)
  device = screenshot.device
  user = device&.user

  payload = {
    source: ENV.fetch("FLY_APP", "bg-backend-staging"),
    user_nickname: user&.nickname,
    device_id: device.id,
    device_screen_width: device.screen_width,
    device_screen_height: device.screen_height,
    device_screenshot_id: screenshot.id,
    wallpaper_id: wallpaper.id,
    captured_at: screenshot.captured_at&.iso8601,
    staging_verification_status: screenshot.verification_status,
    staging_similarity_score: screenshot.similarity_score,
    screenshot: {
      blob_key: screenshot.image.blob.key,
      byte_size: screenshot.image.byte_size,
      content_type: screenshot.image.content_type,
      filename: screenshot.image.filename.to_s,
      download_url: presigned_url_for(screenshot.image.blob)
    },
    wallpaper: {
      blob_key: wallpaper.image.blob.key,
      byte_size: wallpaper.image.byte_size,
      content_type: wallpaper.image.content_type,
      filename: wallpaper.image.filename.to_s,
      download_url: presigned_url_for(wallpaper.image.blob)
    }
  }

  if review
    payload[:expected_verification_status] = review.expected_status
    payload[:reviewed_at] = review.reviewed_at&.iso8601
    payload[:reviewed_by_nickname] = review.reviewed_by&.nickname
  end

  if comparison
    payload[:local_match_status] = comparison.status
    payload[:local_match_score] = comparison.score
    payload[:local_match_strong_match_count] = comparison.strong_match_count
    payload[:local_match_peak_score] = comparison.peak_score
    if review
      payload[:disagreement] = {
        admin_status: review.expected_status,
        local_match_status: comparison.status
      }
    end
  end

  payload
end

if ENV["LIST"] == "1"
  nickname = ENV.fetch("NICKNAME", "").strip
  abort_json("NICKNAME is required for LIST") if nickname.blank?

  user = User.find_by(nickname: nickname)
  abort_json("User not found", nickname: nickname) unless user

  limit = ENV.fetch("LIST_LIMIT", "10").to_i.clamp(1, 50)
  device_ids = user.devices.pluck(:id)
  abort_json("User has no devices", nickname: nickname) if device_ids.empty?

  rows = DeviceScreenshot
    .where(device_id: device_ids)
    .order(captured_at: :desc)
    .limit(limit)
    .map { |screenshot| screenshot_row(screenshot) }

  puts JSON.pretty_generate({ app: ENV.fetch("FLY_APP", "bg-backend-staging"), screenshots: rows })
  exit 0
end

unless TigrisObjectStorage.configured?
  abort_json("Tigris is not configured on this app")
end

if ENV["EXPORT_DISAGREEMENTS"] == "1"
  scope = WallpaperPairReview
    .disagreeing_with_local_match
    .includes(
      :reviewed_by,
      device_screenshot: [
        { image_attachment: :blob },
        :wallpaper_algorithm_comparisons
      ],
      wallpaper: { image_attachment: :blob }
    )
    .order(reviewed_at: :desc)

  pairs = scope.filter_map do |review|
    screenshot = review.device_screenshot
    wallpaper = review.wallpaper
    next unless screenshot&.image&.attached? && wallpaper&.image&.attached?

    comparison = screenshot.wallpaper_algorithm_comparisons.find { |row| row.algorithm == "local_match" }
    next unless comparison

    pair_payload(screenshot, wallpaper, review: review, comparison: comparison)
  end

  puts JSON.pretty_generate({
    source: ENV.fetch("FLY_APP", "bg-backend-staging"),
    exported_at: Time.current.iso8601,
    export_kind: "disagreements",
    algorithm: "local_match",
    pairs: pairs
  })
  exit 0
end

if ENV["EXPORT_LABELED"] == "1"
  scope = WallpaperPairReview
    .includes(:reviewed_by, device_screenshot: { image_attachment: :blob }, wallpaper: { image_attachment: :blob })
    .order(reviewed_at: :desc)

  scope = scope.for_regression if ENV["EXCLUDE_IGNORED"] == "1"

  pairs = scope.filter_map do |review|
    screenshot = review.device_screenshot
    wallpaper = review.wallpaper
    next unless screenshot&.image&.attached? && wallpaper&.image&.attached?

    pair_payload(screenshot, wallpaper, review: review)
  end

  puts JSON.pretty_generate({
    source: ENV.fetch("FLY_APP", "bg-backend-staging"),
    exported_at: Time.current.iso8601,
    pairs: pairs
  })
  exit 0
end

screenshot =
  if ENV["SCREENSHOT_ID"].present?
    DeviceScreenshot.find_by(id: ENV["SCREENSHOT_ID"].to_i) ||
      abort_json("Screenshot not found", screenshot_id: ENV["SCREENSHOT_ID"])
  else
    nickname = ENV.fetch("NICKNAME", "").strip
    abort_json("NICKNAME or SCREENSHOT_ID is required") if nickname.blank?

    user = User.find_by(nickname: nickname)
    abort_json("User not found", nickname: nickname) unless user

    device_ids = user.devices.pluck(:id)
    abort_json("User has no devices", nickname: nickname) if device_ids.empty?

    DeviceScreenshot.where(device_id: device_ids).order(captured_at: :desc).first ||
      abort_json("No screenshots for user", nickname: nickname)
  end

device = screenshot.device
abort_json("Screenshot has no device", device_screenshot_id: screenshot.id) unless device

wallpaper = screenshot.wallpaper_id ? Wallpaper.find_by(id: screenshot.wallpaper_id) : device.current_wallpaper
abort_json("No wallpaper for screenshot", device_screenshot_id: screenshot.id) unless wallpaper
abort_json("Screenshot image missing", device_screenshot_id: screenshot.id) unless screenshot.image.attached?
abort_json("Wallpaper image missing", wallpaper_id: wallpaper.id) unless wallpaper.image.attached?

puts JSON.pretty_generate(pair_payload(screenshot, wallpaper))
