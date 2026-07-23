# frozen_string_literal: true

# Replaces a leverage photo's visible image with a puzzle progress snapshot.
# Purges the original and timelock payload so only the partial board remains.
class LeveragePhotos::CropToProgress
  def self.call(photo:, snapshot:)
    new(photo: photo, snapshot: snapshot).call
  end

  def initialize(photo:, snapshot:)
    @photo = photo
    @snapshot = snapshot
  end

  def call
    raise ArgumentError, "snapshot required" unless @snapshot.respond_to?(:attached?) && @snapshot.attached?
    raise ArgumentError, "photo not eligible" unless @photo.eligible_for_crop_to_progress?

    was_active = @photo.active?
    was_unlocked = @photo.unlocked?

    blob = @snapshot.blob
    teaser_io = build_teaser_io(blob)

    @photo.original_image.purge if @photo.original_image.attached?
    @photo.tlock_blob.purge if @photo.tlock_blob.attached?
    @photo.leverage_photo_extensions.destroy_all

    if @photo.censored_image.attached?
      @photo.censored_image.purge
    end
    @photo.censored_image.attach(
      io: StringIO.new(blob.download),
      filename: "puzzle-progress-#{@photo.id}.png",
      content_type: blob.content_type.presence || "image/png"
    )

    @photo.teaser_image.purge if @photo.teaser_image.attached?
    @photo.teaser_image.attach(
      io: teaser_io,
      filename: "teaser-#{@photo.id}.jpg",
      content_type: "image/jpeg"
    )

    attrs = {
      status: "sanctioned",
      locked_until: nil,
      drand_rounds: [],
      tlock_layer_count: 0,
      drand_chain_hash: nil,
      initial_duration_seconds: nil
    }

    @photo.update!(attrs)
    @photo.assert_attachments!

    if was_active || was_unlocked
      LeveragePhotos::SyncLinkedWallpapers.on_locking!(@photo)
    end

    @photo
  end

  private

  def build_teaser_io(blob)
    processed = ImageProcessing::Vips
      .source(StringIO.new(blob.download))
      .resize_to_limit(50, 50)
      .convert("jpg")
      .call
    StringIO.new(File.binread(processed.path))
  rescue StandardError
    StringIO.new(blob.download)
  ensure
    if processed
      processed.close if processed.respond_to?(:close)
      FileUtils.rm_f(processed.path) if processed.respond_to?(:path)
    end
  end
end
