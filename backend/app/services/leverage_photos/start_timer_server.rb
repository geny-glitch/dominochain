# frozen_string_literal: true

class LeveragePhotos::StartTimerServer
  class Error < StandardError; end

  def initialize(photo:, duration_seconds:)
    @photo = photo
    @duration_seconds = duration_seconds.to_i
  end

  def call!
    raise Error, "photo cannot be locked" unless @photo.draft? || @photo.unlocked?
    raise Error, "no source image available to lock" unless source_available?
    raise Error, "invalid duration" unless @duration_seconds.between?(
      LeveragePhoto::MIN_DURATION_SECONDS,
      LeveragePhoto::MAX_DURATION_SECONDS
    )

    locked_until = Time.current + @duration_seconds.seconds
    crypto = encrypt_for(locked_until)

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

  private

  # A photo re-locked after being unlocked no longer has its plaintext original
  # (it's purged when first locked, see StartTimer#call!). In that case we wrap
  # its still-attached armored tlock_blob with a fresh outer layer instead,
  # the same technique AddTimeServer uses to extend an active lock.
  def source_available?
    @photo.original_image.attached? || @photo.tlock_blob.attached?
  end

  def encrypt_for(locked_until)
    if @photo.original_image.attached?
      LeveragePhotos::TlockCrypto.encrypt_bytes(@photo.original_image.download, locked_until)
    else
      armored = @photo.tlock_blob.download.force_encoding("UTF-8")
      LeveragePhotos::TlockCrypto.encrypt_outer_layer(armored, locked_until)
    end
  end
end
