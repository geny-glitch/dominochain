# frozen_string_literal: true

module ImagePreviewVariant
  extend ActiveSupport::Concern

  # Boss UI grids display ~100–200 CSS px wide; 360px covers 2x retina without shipping full phone captures.
  BOSS_PREVIEW_MAX_WIDTH = 360
  BOSS_PREVIEW_MAX_HEIGHT = 640
  BOSS_PREVIEW_VARIANT_NAME = :boss_preview
  BACKFILL_MODEL_NAMES = %w[Wallpaper DeviceScreenshot].freeze

  class PreviewNotReady < StandardError; end

  module AttachmentConfig
    module_function

    def call(attachable)
      attachable.variant(
        ImagePreviewVariant::BOSS_PREVIEW_VARIANT_NAME,
        resize_to_limit: [ImagePreviewVariant::BOSS_PREVIEW_MAX_WIDTH, ImagePreviewVariant::BOSS_PREVIEW_MAX_HEIGHT],
        saver: { quality: 75 },
        preprocessed: true
      )
    end
  end

  class << self
    def backfill!(async: true)
      blobs = backfill_blobs
      needing = blobs.reject { |blob| preview_variant_processed?(blob) }

      puts "Found #{blobs.size} image blobs, #{needing.size} missing #{BOSS_PREVIEW_VARIANT_NAME} variant"

      needing.each_with_index do |blob, index|
        if async
          blob.preprocessed(boss_preview_named_transformations)
          puts "[#{index + 1}/#{needing.size}] Enqueued #{blob.key}"
        else
          preview_variant_for(blob).processed
          puts "[#{index + 1}/#{needing.size}] Processed #{blob.key}"
        end
      end

      puts async ? "Done. Transform jobs enqueued." : "Done. All variants processed inline."
      needing.size
    end

    def backfill_blobs
      blob_ids = ActiveStorage::Attachment.where(
        record_type: BACKFILL_MODEL_NAMES,
        name: "image"
      ).distinct.pluck(:blob_id)

      ActiveStorage::Blob.where(id: blob_ids).to_a
    end

    def preview_variant_processed?(blob)
      return true unless blob.representable?

      variant = preview_variant_for(blob)
      if ActiveStorage.track_variants
        blob.variant_records.exists?(variation_digest: variant.variation.digest)
      else
        variant.send(:processed?)
      end
    rescue ActiveStorage::UnrepresentableError
      true
    end

    def preview_variant_for(blob)
      blob.representation(boss_preview_named_transformations)
    end

    def open_processed_preview(blob, &block)
      raise PreviewNotReady unless preview_variant_processed?(blob)

      variant = preview_variant_for(blob)
      record = blob.variant_records.find_by!(variation_digest: variant.variation.digest)
      record.image.blob.open(&block)
    end

    def boss_preview_named_transformations
      @boss_preview_named_transformations ||= Wallpaper.reflect_on_attachment(:image)
        .named_variants.fetch(BOSS_PREVIEW_VARIANT_NAME).transformations
    end
  end

  def preview_image
    return image unless image.attached?

    blob = image.blob
    return image unless ImagePreviewVariant.preview_variant_processed?(blob)

    image.variant(BOSS_PREVIEW_VARIANT_NAME)
  end
end
