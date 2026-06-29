# frozen_string_literal: true

class AppUpdateNotifyJob < ApplicationJob
  def perform(version_code, apk_url)
    Device.where.not(fcm_token: [nil, ""]).find_each do |device|
      FcmService.send_app_update_notification(
        device: device,
        version_code: version_code,
        apk_url: apk_url
      )
    end
  end
end
