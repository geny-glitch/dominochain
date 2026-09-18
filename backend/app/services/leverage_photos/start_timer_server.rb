# frozen_string_literal: true

class LeveragePhotos::StartTimerServer
  class Error < StandardError; end

  def initialize(photo:, duration_seconds:)
    @photo = photo
    @duration_seconds = duration_seconds.to_i
  end

  def call!
    # Hold the row lock across encrypt so a parallel lock cannot wrap a stale blob.
    @photo.with_lock do
      raise Error, "photo cannot be locked" unless @photo.draft? || @photo.unlocked?
      raise Error, "no source image available to lock" unless source_available?
      raise Error, "invalid duration" unless @duration_seconds.between?(
        LeveragePhoto::MIN_DURATION_SECONDS,
        LeveragePhoto::MAX_DURATION_SECONDS
      )

      locked_until = Time.current + @duration_seconds.seconds
      crypto, layer_count = encrypt_for(locked_until)

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
        chain_hash: crypto[:chain_hash],
        tlock_layer_count: layer_count
      ).call!
    end
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
      [
        LeveragePhotos::TlockCrypto.encrypt_attachment(
          @photo.original_image,
          locked_until,
          command: "encrypt-bytes"
        ),
        1
      ]
    else
      previous = [@photo.tlock_layer_count.to_i, 1].max
      next_count = previous + 1
      raise Error, "photo cannot be locked" if next_count > LeveragePhoto::MAX_PEEL_LAYERS

      [
        LeveragePhotos::TlockCrypto.encrypt_attachment(
          @photo.tlock_blob,
          locked_until,
          command: "encrypt-outer"
        ),
        next_count
      ]
    end
  end
end
