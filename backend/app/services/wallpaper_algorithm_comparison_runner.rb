# frozen_string_literal: true

class WallpaperAlgorithmComparisonRunner
  class PreviewNotReady < StandardError; end
  class CompareTimeout < StandardError; end

  COMPARE_TIMEOUT = 90.seconds

  def initialize(screenshot:, algorithm:)
    @screenshot = screenshot
    @wallpaper = screenshot.wallpaper
    @device = screenshot.device
    @algorithm = algorithm
  end

  def run!
    raise ArgumentError, "Unknown algorithm: #{@algorithm}" unless AppSetting::WALLPAPER_VERIFICATION_ALGORITHMS.key?(@algorithm)
    raise ArgumentError, "Screenshot has no wallpaper" unless @wallpaper&.image&.attached?
    raise ArgumentError, "Screenshot image missing" unless @screenshot.image.attached?

    ensure_previews_ready!

    result = nil
    Timeout.timeout(COMPARE_TIMEOUT) do
      result = WallpaperScreenshotComparator.new(
        screenshot: @screenshot,
        wallpaper: @wallpaper,
        device: @device,
        algorithm: @algorithm
      ).compare
    end

    WallpaperAlgorithmComparison.upsert_from_result!(
      device_screenshot: @screenshot,
      algorithm: @algorithm,
      result: result
    )
  rescue Timeout::Error
    raise CompareTimeout, "Comparison timed out after #{COMPARE_TIMEOUT.to_i}s"
  rescue ImagePreviewVariant::PreviewNotReady
    raise PreviewNotReady, "Image previews are not ready yet"
  end

  private

  def ensure_previews_ready!
    [@screenshot.image.blob, @wallpaper.image.blob].each do |blob|
      next if ImagePreviewVariant.preview_variant_processed?(blob)

      ImagePreviewVariant.preview_variant_for(blob).processed
    end

    ready = ImagePreviewVariant.preview_variant_processed?(@screenshot.image.blob) &&
            ImagePreviewVariant.preview_variant_processed?(@wallpaper.image.blob)
    raise PreviewNotReady, "Image previews are not ready yet" unless ready
  end
end
