# frozen_string_literal: true

class LeveragePhotos::AddTimeServer
  class Error < StandardError; end

  def initialize(photo:, added_seconds:)
    @photo = photo
    @added_seconds = added_seconds.to_i
  end

  def call!
    raise Error, "cannot add time" unless @photo.can_add_time?
    raise Error, "invalid added_seconds" if @added_seconds <= 0

    base = @photo.locked_until.presence || Time.current
    from = [base, Time.current].max
    locked_until = from + @added_seconds.seconds

    current_armored = @photo.tlock_blob.download.force_encoding("UTF-8")
    crypto = LeveragePhotos::TlockCrypto.encrypt_outer_layer(current_armored, locked_until)

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
  rescue LeveragePhotos::AddTime::Error, LeveragePhotos::TlockCrypto::Error => e
    raise Error, e.message
  end
end
