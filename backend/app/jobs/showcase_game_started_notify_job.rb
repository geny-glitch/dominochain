# frozen_string_literal: true

class ShowcaseGameStartedNotifyJob < ApplicationJob
  queue_as :default

  def perform(user_id, game_session_id, game_type, player_name = nil)
    user = User.find_by(id: user_id)
    return unless user

    user.devices.find_each do |device|
      notification_args = {
        device: device,
        game_session_id: game_session_id,
        game_type: game_type
      }
      notification_args[:player_name] = player_name if player_name.present?
      FcmService.send_showcase_game_started_notification(**notification_args)
    end
  end
end
