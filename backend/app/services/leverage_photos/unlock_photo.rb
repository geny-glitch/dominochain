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
    restore_envelope_if_needed!
    @photo
  end

  private

  def restore_envelope_if_needed!
    return unless @photo.unlocked?
    return if @photo.viewable_original?
    return unless @photo.encrypted_original.attached? && @photo.tlock_blob.attached?

    LeveragePhotos::Envelope.open!(@photo)
  rescue LeveragePhotos::Envelope::Error, LeveragePhotos::TlockCrypto::Error => e
    Rails.logger.warn(
      "[LeveragePhotoUnlock] photo=#{@photo.id} envelope restore failed: #{e.class}: #{e.message}"
    )
  end
end
