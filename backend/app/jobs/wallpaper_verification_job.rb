# frozen_string_literal: true

class WallpaperVerificationJob < ApplicationJob
  queue_as :wallpaper_verification

  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionFailed, wait: 5.seconds, attempts: 3
  retry_on PG::ConnectionBad, wait: 5.seconds, attempts: 3

  def perform(screenshot_id)
    screenshot = DeviceScreenshot.includes(device: :wallpapers).find_by(id: screenshot_id)
    return unless screenshot&.image&.attached?

    device = screenshot.device
    wallpaper = device.current_wallpaper
    unless wallpaper&.image&.attached?
      update_screenshot!(screenshot, wallpaper_id: nil, verification_status: "skipped")
      return
    end

    latest_application = device.wallpaper_applications.recent.first
    if latest_application && screenshot.captured_at < latest_application.applied_at
      update_screenshot!(
        screenshot,
        wallpaper_id: wallpaper.id,
        verification_status: "inconclusive"
      )
      return
    end

    # Vips is memory-heavy; release DB pool slots before image work so web requests keep connections.
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)

    result = WallpaperScreenshotComparator.new(
      screenshot: screenshot,
      wallpaper: wallpaper,
      device: device
    ).compare

    update_screenshot!(
      screenshot,
      wallpaper_id: wallpaper.id,
      similarity_score: result.score,
      verification_status: result.status
    )

    Rails.logger.info(
      "[WallpaperVerification] screenshot=#{screenshot.id} device=#{device.device_id} " \
      "status=#{result.status} score=#{result.score} ssim=#{result.ssim} dhash=#{result.dhash_distance}"
    )
  rescue Vips::Error, ActiveStorage::FileNotFoundError => e
    Rails.logger.warn("[WallpaperVerification] screenshot=#{screenshot_id} failed: #{e.class}: #{e.message}")
    update_screenshot!(screenshot, verification_status: "inconclusive") if screenshot
  end

  private

  def update_screenshot!(screenshot, **attrs)
    screenshot.update!(attrs.merge(verified_at: Time.current))
  end
end
