# frozen_string_literal: true

class LeveragePhotos::AddTimeServer
  class Error < StandardError; end

  def initialize(photo:, added_seconds:)
    @photo = photo
    @added_seconds = added_seconds.to_i
  end

  def call!
    raise Error, "invalid added_seconds" if @added_seconds <= 0

    # Hold the row lock across encrypt so a parallel extend cannot wrap a stale blob.
    @photo.with_lock do
      raise Error, "cannot add time" unless @photo.can_add_time?

      base = @photo.locked_until.presence || Time.current
      from = [base, Time.current].max
      locked_until = from + @added_seconds.seconds

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
        added_seconds: @added_seconds
      ).call!
    end
  rescue LeveragePhotos::AddTime::Error, LeveragePhotos::TlockCrypto::Error => e
    raise Error, e.message
  end
end
