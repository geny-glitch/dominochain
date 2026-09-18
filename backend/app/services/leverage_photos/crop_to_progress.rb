# frozen_string_literal: true

# Adds a puzzle progress snapshot as a new censored version and removes the original.
# Existing censored versions are left untouched.
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

    @photo.original_image.purge if @photo.original_image.attached?
    @photo.tlock_blob.purge if @photo.tlock_blob.attached?
    @photo.encrypted_original.purge if @photo.encrypted_original.attached?
    @photo.leverage_photo_extensions.destroy_all

    @photo.censored_images.attach(
      io: StringIO.new(blob.download),
      filename: "puzzle-progress-#{@photo.id}.png",
      content_type: blob.content_type.presence || "image/png"
    )

    attrs = {
      status: "sanctioned",
      locked_until: nil,
      drand_rounds: [],
      tlock_layer_count: 0,
      drand_chain_hash: nil,
      tlock_format: LeveragePhoto::TLOCK_FORMAT_FULL_IMAGE,
      initial_duration_seconds: nil,
      add_time_base_seconds: nil,
      add_time_step_n: 0
    }

    @photo.update!(attrs)
    @photo.assert_attachments!

    if was_active || was_unlocked
      LeveragePhotos::SyncLinkedWallpapers.on_locking!(@photo)
    end

    @photo
  end
end
