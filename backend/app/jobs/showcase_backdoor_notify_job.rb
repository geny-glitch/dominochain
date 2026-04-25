# frozen_string_literal: true

class ShowcaseBackdoorNotifyJob < ApplicationJob
  queue_as :default

  def perform(user_id, player_name, seconds, message)
    user = User.find_by(id: user_id)
    return unless user

    user.devices.find_each do |device|
      FcmService.send_showcase_backdoor_notification(
        device: device,
        player_name: player_name,
        seconds: seconds,
        message: message
      )
    end
  end
end
