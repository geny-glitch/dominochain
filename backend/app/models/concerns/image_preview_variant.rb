# frozen_string_literal: true

module ImagePreviewVariant
  extend ActiveSupport::Concern

  # Boss UI grids display ~100–200 CSS px wide; 360px covers 2x retina without shipping full phone captures.
  BOSS_PREVIEW_MAX_WIDTH = 360
  BOSS_PREVIEW_MAX_HEIGHT = 640

  def preview_image
    return image unless image.attached?

    image.variant(
      resize_to_limit: [BOSS_PREVIEW_MAX_WIDTH, BOSS_PREVIEW_MAX_HEIGHT],
      saver: { quality: 75 }
    )
  end
end
