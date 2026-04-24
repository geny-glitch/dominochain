# frozen_string_literal: true

class ShowcaseBetaNotifyJob < ApplicationJob
  queue_as :default

  def perform(user_id, player_name, score, game_type)
    user = User.find_by(id: user_id)
    return unless user

    user.devices.find_each do |device|
      FcmService.send_showcase_game_notification(
        device: device,
        player_name: player_name,
        score: score,
        game_type: game_type
      )
    end
  end
end
