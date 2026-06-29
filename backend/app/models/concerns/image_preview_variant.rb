# frozen_string_literal: true

module ImagePreviewVariant
  extend ActiveSupport::Concern

  # Boss UI grids display ~100–200 CSS px wide; 360px covers 2x retina without shipping full phone captures.
  BOSS_PREVIEW_MAX_WIDTH = 360
  BOSS_PREVIEW_MAX_HEIGHT = 640
  BOSS_PREVIEW_VARIANT_NAME = :boss_preview

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

  def preview_image
    return image unless image.attached?

    image.variant(BOSS_PREVIEW_VARIANT_NAME)
  end
end
