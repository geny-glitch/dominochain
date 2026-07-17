# frozen_string_literal: true

class LeveragePhotos::StartTimerServer
  class Error < StandardError; end

  def initialize(photo:, duration_seconds:)
    @photo = photo
    @duration_seconds = duration_seconds.to_i
  end

  def call!
    raise Error, "photo must be draft" unless @photo.draft?
    raise Error, "original missing" unless @photo.original_image.attached?
    raise Error, "invalid duration" unless @duration_seconds.between?(
      LeveragePhoto::MIN_DURATION_SECONDS,
      LeveragePhoto::MAX_DURATION_SECONDS
    )

    locked_until = Time.current + @duration_seconds.seconds
    bytes = @photo.original_image.download
    crypto = LeveragePhotos::TlockCrypto.encrypt_bytes(bytes, locked_until)

    blob = {
      io: StringIO.new(crypto[:armored]),
      filename: "layer.tlock",
      content_type: "text/plain"
    }

    LeveragePhotos::StartTimer.new(
      photo: @photo,
      tlock_blob: blob,
      drand_round: crypto[:round],
      locked_until: locked_until,
      duration_seconds: @duration_seconds,
      chain_hash: crypto[:chain_hash]
    ).call!
  rescue LeveragePhotos::StartTimer::Error, LeveragePhotos::TlockCrypto::Error => e
    raise Error, e.message
  end
end
