# frozen_string_literal: true

class LeveragePhotoUnlockJob < ApplicationJob
  queue_as :default

  def perform(reference_time_iso8601 = nil)
    reference_time = reference_time_iso8601.present? ? Time.zone.parse(reference_time_iso8601) : Time.current

    LeveragePhoto.due_for_unlock(reference_time).find_each do |photo|
      photo.mark_unlocked!
      Rails.logger.info("[LeveragePhotoUnlock] photo=#{photo.id} user=#{photo.user_id} unlocked")
    rescue StandardError => e
      Rails.logger.warn(
        "[LeveragePhotoUnlock] photo=#{photo.id} failed: #{e.class}: #{e.message}"
      )
    end
  end
end
