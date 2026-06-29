# frozen_string_literal: true

class WallpaperVerificationJob < ApplicationJob
  queue_as :wallpaper_verification

  def perform(screenshot_id)
    screenshot = DeviceScreenshot.find_by(id: screenshot_id)
    return unless screenshot&.image&.attached?

    device = screenshot.device
    wallpaper = device.current_wallpaper
    unless wallpaper&.image&.attached?
      screenshot.update!(
        verification_status: "skipped",
        verified_at: Time.current
      )
      return
    end

    latest_application = device.wallpaper_applications.recent.first
    if latest_application && screenshot.captured_at < latest_application.applied_at
      screenshot.update!(
        wallpaper_id: wallpaper.id,
        verification_status: "inconclusive",
        verified_at: Time.current
      )
      return
    end

    result = WallpaperScreenshotComparator.new(
      screenshot: screenshot,
      wallpaper: wallpaper,
      device: device
    ).compare

    screenshot.update!(
      wallpaper_id: wallpaper.id,
      similarity_score: result.score,
      verification_status: result.status,
      verified_at: Time.current
    )

    Rails.logger.info(
      "[WallpaperVerification] screenshot=#{screenshot.id} device=#{device.device_id} " \
      "status=#{result.status} score=#{result.score} ssim=#{result.ssim} dhash=#{result.dhash_distance}"
    )
  rescue Vips::Error, ActiveStorage::FileNotFoundError => e
    Rails.logger.warn("[WallpaperVerification] screenshot=#{screenshot_id} failed: #{e.class}: #{e.message}")
    screenshot&.update!(
      verification_status: "inconclusive",
      verified_at: Time.current
    )
  end
end
