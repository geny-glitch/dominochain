# frozen_string_literal: true

class WallpaperScreenshotRequestJob < ApplicationJob
  def perform(device_id, wallpaper_applied_at_iso8601)
    device = Device.find_by(id: device_id)
    return unless device

    applied_at = Time.zone.parse(wallpaper_applied_at_iso8601.to_s)
    return unless applied_at

    recent_screenshot = device.device_screenshots.where(captured_at: applied_at..).exists?
    return if recent_screenshot

    FcmService.send_take_screenshot_notification(device: device)
  end
end
