# frozen_string_literal: true

class LeveragePhotos::UnlockPhoto
  def self.call!(photo)
    new(photo).call!
  end

  def initialize(photo)
    @photo = photo
  end

  def call!
    return @photo unless @photo

    @photo.mark_unlocked! if @photo.unlock_due?
    enqueue_restore_if_needed!
    @photo
  end

  private

  def enqueue_restore_if_needed!
    return unless @photo.unlocked?
    return if @photo.viewable_original?
    return unless @photo.tlock_blob.attached?

    LeveragePhotos::RestorePayloadJob.perform_later(@photo.id)
  end
end
