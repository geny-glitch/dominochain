# frozen_string_literal: true

class LeveragePhotos::RestorePayload
  class Error < StandardError; end

  def self.call!(photo)
    new(photo).call!
  end

  def initialize(photo)
    @photo = photo
  end

  def call!
    return @photo unless @photo
    return @photo if @photo.viewable_original?

    @photo.with_lock do
      @photo.reload
      return @photo if @photo.viewable_original?
      raise Error, "photo is still locked" unless @photo.unlocked?

      if @photo.encrypted_original.attached? && @photo.tlock_blob.attached?
        LeveragePhotos::Envelope.open!(@photo)
      elsif @photo.tlock_blob.attached?
        peel_full_image!
      else
        raise Error, "locked payload missing"
      end
    end

    @photo
  rescue LeveragePhotos::Envelope::Error, LeveragePhotos::TlockCrypto::Error => e
    raise Error, e.message
  end

  private

  def peel_full_image!
    bytes = LeveragePhotos::TlockCrypto.decrypt_attachment(@photo.tlock_blob)
    @photo.persist_restored_original!(
      io: StringIO.new(bytes),
      filename: @photo.download_filename,
      content_type: "image/jpeg"
    )
  end
end
