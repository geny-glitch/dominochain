# frozen_string_literal: true

class LeveragePhotos::AddTimeServer
  class Error < StandardError; end

  def initialize(photo:, added_seconds:, save_as_base: false, apply_next_step: false, locked_until: nil)
    @photo = photo
    @added_seconds = added_seconds.to_i
    @save_as_base = save_as_base
    @apply_next_step = apply_next_step
    @locked_until = locked_until
  end

  def call!
    raise Error, "invalid added_seconds" if @added_seconds <= 0

    # Hold the row lock across encrypt so a parallel extend cannot wrap a stale blob.
    @photo.with_lock do
      raise Error, "cannot add time" unless @photo.can_add_time?

      locked_until =
        if @locked_until.present?
          @locked_until
        else
          base = @photo.locked_until.presence || Time.current
          [base, Time.current].max + @added_seconds.seconds
        end

      crypto, layer_count, tlock_format, encrypted_original = encrypt_for(locked_until)

      blob = {
        io: StringIO.new(crypto[:armored]),
        filename: "layer.tlock",
        content_type: "text/plain"
      }

      LeveragePhotos::AddTime.new(
        photo: @photo,
        tlock_blob: blob,
        drand_round: crypto[:round],
        locked_until: locked_until,
        added_seconds: @added_seconds,
        save_as_base: @save_as_base,
        apply_next_step: @apply_next_step,
        tlock_format: tlock_format,
        tlock_layer_count: layer_count,
        encrypted_original: encrypted_original
      ).call!
    end
  rescue LeveragePhotos::TlockCrypto::Error, LeveragePhotos::Envelope::Error => e
    Rails.logger.error("[AddTimeServer] #{e.class}: #{e.message}")
    raise Error, I18n.t("flash.beta.leverage_photo.secure_failed")
  rescue LeveragePhotos::AddTime::Error => e
    raise Error, e.message
  end

  private

  def encrypt_for(locked_until)
    if @photo.full_image_lock?
      packed, crypto = LeveragePhotos::Envelope.new(@photo).wrap_existing_blob(locked_until)
      [
        crypto,
        1,
        LeveragePhoto::TLOCK_FORMAT_ENVELOPE,
        {
          io: StringIO.new(packed),
          filename: "original.bin",
          content_type: "application/octet-stream"
        }
      ]
    else
      previous = [@photo.tlock_layer_count.to_i, 1].max
      next_count = previous + 1
      raise Error, "cannot add time" if next_count > LeveragePhoto::MAX_TLOCK_LAYERS

      [
        LeveragePhotos::TlockCrypto.encrypt_attachment(
          @photo.tlock_blob,
          locked_until,
          command: "encrypt-outer"
        ),
        next_count,
        LeveragePhoto::TLOCK_FORMAT_ENVELOPE,
        nil
      ]
    end
  end
end
