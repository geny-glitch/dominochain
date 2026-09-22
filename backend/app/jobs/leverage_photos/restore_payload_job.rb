# frozen_string_literal: true

class LeveragePhotos::RestorePayloadJob < ApplicationJob
  queue_as :default

  def perform(photo_id)
    photo = LeveragePhoto.find_by(id: photo_id)
    return unless photo

    LeveragePhotos::RestorePayload.call!(photo)
  rescue LeveragePhotos::RestorePayload::Error => e
    Rails.logger.warn(
      "[LeveragePhotoRestore] photo=#{photo_id} failed: #{e.class}: #{e.message}"
    )
  end
end
