# frozen_string_literal: true

class PishockShockJob < ApplicationJob
  queue_as :default

  def perform(user_id, intensity, duration)
    user = User.find_by(id: user_id)
    return unless user

    PishockService.shock!(user: user, intensity: intensity, duration: duration)
  end
end
