# frozen_string_literal: true

class ShowcaseGameStartedNotifyJob < ApplicationJob
  queue_as :default

  def perform(user_id, game_session_id, game_type)
    user = User.find_by(id: user_id)
    return unless user

    user.devices.find_each do |device|
      FcmService.send_showcase_game_started_notification(
        device: device,
        game_session_id: game_session_id,
        game_type: game_type
      )
    end
  end
end
