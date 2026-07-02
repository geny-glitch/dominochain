# frozen_string_literal: true

class WallpaperMismatchRecheckJob < ApplicationJob
  queue_as :default

  DOUBLE_CHECK_WAIT = 10.seconds

  def perform(device_id)
    device = Device.find_by(id: device_id)
    return unless device&.fcm_token.present?

    user = device.user
    config = user&.wallpaper_enforcement_config
    return unless config&.enabled?
    return unless config.mismatch_sanction_mode == WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK

    FcmService.send_take_screenshot_notification(
      device: device,
      dismiss_apps: config.dismiss_apps_before_capture
    )
  end
end
