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

      crypto = LeveragePhotos::TlockCrypto.encrypt_attachment(
        @photo.tlock_blob,
        locked_until,
        command: "encrypt-outer"
      )

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
        apply_next_step: @apply_next_step
      ).call!
    end
  rescue LeveragePhotos::TlockCrypto::Error => e
    Rails.logger.error("[AddTimeServer] #{e.class}: #{e.message}")
    raise Error, I18n.t("flash.beta.leverage_photo.secure_failed")
  rescue LeveragePhotos::AddTime::Error => e
    raise Error, e.message
  end
end
