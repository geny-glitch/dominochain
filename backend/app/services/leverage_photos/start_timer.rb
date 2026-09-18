# frozen_string_literal: true

class LeveragePhotos::StartTimer
  class Error < StandardError; end

  def initialize(photo:, tlock_blob:, drand_round:, locked_until:, duration_seconds:, chain_hash: nil, tlock_layer_count: 1, tlock_format: nil, encrypted_original: nil)
    @photo = photo
    @tlock_blob = tlock_blob
    @drand_round = drand_round.to_i
    @locked_until = locked_until
    @duration_seconds = duration_seconds.to_i
    @chain_hash = chain_hash.presence || LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    @tlock_layer_count = tlock_layer_count.to_i
    @tlock_format = tlock_format.presence || photo.tlock_format.presence || LeveragePhoto::TLOCK_FORMAT_FULL_IMAGE
    @encrypted_original = encrypted_original
  end

  def call!
    raise Error, "tlock blob missing" if @tlock_blob.blank?
    raise Error, "invalid round" if @drand_round <= 0
    raise Error, "invalid locked_until" if @locked_until.blank? || @locked_until <= Time.current
    raise Error, "invalid duration" unless @duration_seconds.between?(
      LeveragePhoto::MIN_DURATION_SECONDS,
      LeveragePhoto::MAX_DURATION_SECONDS
    )
    raise Error, "invalid layer count" unless @tlock_layer_count.between?(1, LeveragePhoto::MAX_PEEL_LAYERS)
    raise Error, "invalid tlock format" unless LeveragePhoto::TLOCK_FORMATS.include?(@tlock_format)

    touched_devices = []
    # Serialize lock/extend on this row so a second request (double-submit,
    # event + button, two tabs) re-checks status after the first commit.
    @photo.with_lock do
      raise Error, "photo cannot be locked" unless @photo.draft? || @photo.unlocked?
      raise Error, "original missing" if @photo.draft? && !@photo.original_image.attached?

      if @photo.unlocked?
        @photo.tlock_blob.purge if @photo.tlock_blob.attached?
        @photo.leverage_photo_extensions.destroy_all
      end
      touched_devices = LeveragePhotos::SyncLinkedWallpapers.on_locking!(@photo, notify: false)
      @photo.tlock_blob.attach(@tlock_blob)
      attach_encrypted_original!
      purge_encrypted_original_for_full_image!
      @photo.original_image.purge if @photo.original_image.attached?
      @photo.update!(
        status: "active",
        locked_until: @locked_until,
        initial_duration_seconds: @duration_seconds,
        add_time_base_seconds: nil,
        add_time_step_n: 0,
        drand_rounds: [@drand_round],
        drand_chain_hash: @chain_hash,
        tlock_format: @tlock_format,
        tlock_layer_count: @tlock_layer_count
      )
      if @tlock_format == LeveragePhoto::TLOCK_FORMAT_ENVELOPE && !@photo.encrypted_original.attached?
        raise Error, "encrypted original missing"
      end
      @photo.assert_attachments!
    end

    FcmService.send_background_changed_notifications_to_devices(devices: touched_devices) if touched_devices.any?

    @photo
  end

  private

  def attach_encrypted_original!
    return if @encrypted_original.blank?

    @photo.encrypted_original.purge if @photo.encrypted_original.attached?
    @photo.encrypted_original.attach(@encrypted_original)
  end

  def purge_encrypted_original_for_full_image!
    return unless @tlock_format == LeveragePhoto::TLOCK_FORMAT_FULL_IMAGE
    return unless @photo.encrypted_original.attached?

    @photo.encrypted_original.purge
  end
end
