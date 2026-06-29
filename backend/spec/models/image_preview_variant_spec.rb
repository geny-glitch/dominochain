# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImagePreviewVariant do
  include ActiveJob::TestHelper

  describe "boss preview pre-processing" do
    it "enqueues a transform job when a wallpaper image is attached" do
      wallpaper = create(:wallpaper)

      expect do
        WallpaperVerificationTestImages.attach_png(
          wallpaper,
          attachment_name: :image,
          width: 1080,
          height: 1920,
          color: [120, 80, 200]
        )
      end.to have_enqueued_job(ActiveStorage::TransformJob)
    end

    it "enqueues a transform job when a screenshot image is attached" do
      screenshot = create(:device_screenshot)

      expect do
        WallpaperVerificationTestImages.attach_png(
          screenshot,
          attachment_name: :image,
          width: 1080,
          height: 1920,
          color: [40, 40, 40]
        )
      end.to have_enqueued_job(ActiveStorage::TransformJob)
    end

    it "returns the named boss preview variant" do
      wallpaper = create(:wallpaper)
      WallpaperVerificationTestImages.attach_png(
        wallpaper,
        attachment_name: :image,
        width: 1080,
        height: 1920,
        color: [120, 80, 200]
      )

      preview = wallpaper.preview_image

      expect(preview).to be_a(ActiveStorage::VariantWithRecord)
      expect(preview.variation.transformations).to include(
        resize_to_limit: [ImagePreviewVariant::BOSS_PREVIEW_MAX_WIDTH, ImagePreviewVariant::BOSS_PREVIEW_MAX_HEIGHT],
        saver: { quality: 75 }
      )
    end
  end

  describe ".backfill!" do
    include ActiveJob::TestHelper

    it "enqueues transform jobs only for blobs missing the boss preview variant" do
      wallpaper = create(:wallpaper)
      screenshot = create(:device_screenshot)
      WallpaperVerificationTestImages.attach_png(
        wallpaper,
        attachment_name: :image,
        width: 1080,
        height: 1920,
        color: [120, 80, 200]
      )
      WallpaperVerificationTestImages.attach_png(
        screenshot,
        attachment_name: :image,
        width: 1080,
        height: 1920,
        color: [40, 40, 40]
      )

      clear_enqueued_jobs

      expect do
        ImagePreviewVariant.backfill!(async: true)
      end.to have_enqueued_job(ActiveStorage::TransformJob).twice

      perform_enqueued_jobs

      expect do
        ImagePreviewVariant.backfill!(async: true)
      end.not_to have_enqueued_job(ActiveStorage::TransformJob)
    end

    it "processes missing variants inline when async is false" do
      wallpaper = create(:wallpaper)
      WallpaperVerificationTestImages.attach_png(
        wallpaper,
        attachment_name: :image,
        width: 1080,
        height: 1920,
        color: [120, 80, 200]
      )

      expect(ImagePreviewVariant.backfill!(async: false)).to eq(1)
      expect(ImagePreviewVariant.preview_variant_processed?(wallpaper.image.blob)).to be(true)
    end
  end
end
