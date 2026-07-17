# frozen_string_literal: true

class LeveragePhotos::StartTimer
  class Error < StandardError; end

  def initialize(photo:, tlock_blob:, drand_round:, locked_until:, duration_seconds:, chain_hash: nil)
    @photo = photo
    @tlock_blob = tlock_blob
    @drand_round = drand_round.to_i
    @locked_until = locked_until
    @duration_seconds = duration_seconds.to_i
    @chain_hash = chain_hash.presence || LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
  end

  def call!
    raise Error, "photo cannot be locked" unless @photo.draft? || @photo.unlocked?
    raise Error, "original missing" if @photo.draft? && !@photo.original_image.attached?
    raise Error, "tlock blob missing" if @tlock_blob.blank?
    raise Error, "invalid round" if @drand_round <= 0
    raise Error, "invalid locked_until" if @locked_until.blank? || @locked_until <= Time.current
    raise Error, "invalid duration" unless @duration_seconds.between?(
      LeveragePhoto::MIN_DURATION_SECONDS,
      LeveragePhoto::MAX_DURATION_SECONDS
    )

    touched_devices = []
    LeveragePhoto.transaction do
      if @photo.unlocked?
        @photo.tlock_blob.purge if @photo.tlock_blob.attached?
        @photo.leverage_photo_extensions.destroy_all
      end
      touched_devices = LeveragePhotos::SyncLinkedWallpapers.on_locking!(@photo, notify: false)
      @photo.tlock_blob.attach(@tlock_blob)
      @photo.original_image.purge if @photo.original_image.attached?
      @photo.update!(
        status: "active",
        locked_until: @locked_until,
        initial_duration_seconds: @duration_seconds,
        drand_rounds: [@drand_round],
        drand_chain_hash: @chain_hash,
        tlock_layer_count: 1
      )
      @photo.assert_attachments!
    end

    FcmService.send_background_changed_notifications_to_devices(devices: touched_devices) if touched_devices.any?

    @photo
  end
end
