# frozen_string_literal: true

require "vips"

class WallpaperScreenshotComparator
  ComparisonResult = Struct.new(:score, :status, :ssim, :dhash_distance, :mad, keyword_init: true)

  COMPARE_SIZE = 64
  TOP_MARGIN_RATIO = 0.08
  BOTTOM_MARGIN_RATIO = 0.05

  def initialize(screenshot:, wallpaper:, device:)
    @screenshot = screenshot
    @wallpaper = wallpaper
    @device = device
  end

  def compare
    screenshot_image = load_attachment(@screenshot.image)
    reference_image = load_wallpaper_reference

    full_metrics = metrics_for(screenshot_image, reference_image)
    edge_metrics = metrics_for(screenshot_image, reference_image, edges_only: true)

    best_metrics = [full_metrics, edge_metrics].max_by { |metrics| metrics[:score] }
    classify(**best_metrics.slice(:ssim, :dhash_distance, :mad))
  end

  def metrics_for(screenshot_image, reference_image, edges_only: false)
    screenshot_norm = normalize(screenshot_image, edges_only: edges_only)
    reference_norm = normalize(reference_image, edges_only: edges_only)

    ssim = compute_ssim(screenshot_norm, reference_norm)
    dhash_distance = hamming_distance(
      compute_dhash(screenshot_norm),
      compute_dhash(reference_norm)
    )
    mad = mean_absolute_difference(screenshot_norm, reference_norm)
    score = composite_score(ssim, dhash_distance, mad)

    { ssim: ssim, dhash_distance: dhash_distance, mad: mad, score: score }
  end

  private

  def load_attachment(attachment)
    attachment.blob.open do |file|
      materialize(Vips::Image.new_from_file(file.path, access: :sequential))
    end
  end

  def load_wallpaper_reference
    variant = @wallpaper.variant_for(@device)
    variant.processed.blob.open do |file|
      materialize(Vips::Image.new_from_file(file.path, access: :sequential))
    end
  end

  def materialize(image)
    data = image.write_to_memory
    Vips::Image.new_from_memory(data, image.width, image.height, image.bands, :uchar)
  end

  def normalize(image, edges_only: false)
    cropped = crop_margins(image)
    cropped = crop_edges(cropped) if edges_only
    resized = resize_to_device(cropped)
    blurred = resized.gaussblur(1.5)
    grey = blurred.colourspace("b-w")
    scale = COMPARE_SIZE.to_f / [grey.width, grey.height].max
    materialize(grey.resize(scale, vscale: scale))
  end

  def crop_edges(image)
    width = image.width
    height = image.height
    crop_width = [(width * 0.5).round, 1].max
    crop_height = [(height * 0.5).round, 1].max
    image.crop(0, 0, crop_width, crop_height)
  end

  def crop_margins(image)
    width = image.width
    height = image.height
    top = (height * TOP_MARGIN_RATIO).round
    bottom = (height * BOTTOM_MARGIN_RATIO).round
    crop_height = [height - top - bottom, 1].max
    image.crop(0, top, width, crop_height)
  end

  def resize_to_device(image)
    target_width = @device.screen_width.presence || image.width
    target_height = @device.screen_height.presence || image.height
    image.resize(
      target_width.to_f / image.width,
      vscale: target_height.to_f / image.height
    )
  end

  def compute_dhash(image)
    small = image.colourspace("b-w").resize(9.0 / image.width, vscale: 8.0 / image.height)
    pixels = small.write_to_memory.unpack("C*")
    hash = 0
    64.times do |index|
      row = index / 8
      col = index % 8
      left = pixels[(row * 9) + col]
      right = pixels[(row * 9) + col + 1]
      hash = (hash << 1) | (left > right ? 1 : 0)
    end
    hash
  end

  def hamming_distance(hash_a, hash_b)
    xor = hash_a ^ hash_b
    count = 0
    64.times do
      count += xor & 1
      xor >>= 1
    end
    count
  end

  def compute_ssim(image_a, image_b)
    pixels_a = pixel_values(image_a)
    pixels_b = pixel_values(image_b)

    n = pixels_a.length.to_f
    mu_a = pixels_a.sum / n
    mu_b = pixels_b.sum / n
    sigma_a_sq = pixels_a.sum { |value| (value - mu_a)**2 } / n
    sigma_b_sq = pixels_b.sum { |value| (value - mu_b)**2 } / n
    sigma_ab = pixels_a.zip(pixels_b).sum { |a, b| (a - mu_a) * (b - mu_b) } / n

    k1 = 0.01
    k2 = 0.03
    dynamic_range = 255.0
    c1 = (k1 * dynamic_range)**2
    c2 = (k2 * dynamic_range)**2

    numerator = (2 * mu_a * mu_b + c1) * (2 * sigma_ab + c2)
    denominator = (mu_a**2 + mu_b**2 + c1) * (sigma_a_sq + sigma_b_sq + c2)
    return 0.0 if denominator.zero?

    (numerator / denominator).clamp(0.0, 1.0)
  end

  def pixel_values(image)
    image.write_to_memory.unpack("C*")
  end

  def mean_absolute_difference(image_a, image_b)
    pixels_a = pixel_values(image_a)
    pixels_b = pixel_values(image_b)
    pixels_a.zip(pixels_b).sum { |a, b| (a - b).abs } / pixels_a.length.to_f
  end

  def composite_score(ssim, dhash_distance, mad)
    dhash_similarity = 1.0 - (dhash_distance.to_f / 64.0)
    mad_similarity = 1.0 - [mad / 255.0, 1.0].min
    ((ssim + dhash_similarity + mad_similarity) / 3.0).round(3)
  end

  def classify(ssim:, dhash_distance:, mad:)
    ssim_threshold = ENV.fetch("WALLPAPER_SSIM_THRESHOLD", "0.75").to_f
    dhash_threshold = ENV.fetch("WALLPAPER_DHASH_THRESHOLD", "15").to_i
    score_threshold = ENV.fetch("WALLPAPER_SCORE_THRESHOLD", "0.65").to_f
    score_dhash_max = ENV.fetch("WALLPAPER_SCORE_DHASH_MAX", "18").to_i
    score_mad_max = ENV.fetch("WALLPAPER_SCORE_MAD_MAX", "25").to_f
    mismatch_ssim = ENV.fetch("WALLPAPER_MISMATCH_SSIM", "0.5").to_f
    mismatch_dhash = ENV.fetch("WALLPAPER_MISMATCH_DHASH", "20").to_i
    mad_match_threshold = ENV.fetch("WALLPAPER_MAD_MATCH_THRESHOLD", "18").to_f
    mad_mismatch_threshold = ENV.fetch("WALLPAPER_MAD_MISMATCH_THRESHOLD", "45").to_f

    score = composite_score(ssim, dhash_distance, mad)
    dhash_match = dhash_distance <= dhash_threshold && mad <= mad_match_threshold
    score_match = score >= score_threshold &&
                  dhash_distance <= score_dhash_max &&
                  mad <= score_mad_max

    status = if ssim >= ssim_threshold || dhash_match || score_match || mad <= (mad_match_threshold / 2.0)
      "verified"
    elsif (ssim < mismatch_ssim && dhash_distance > mismatch_dhash && mad > mad_mismatch_threshold) ||
          mad > (mad_mismatch_threshold * 1.5)
      "mismatch"
    else
      "inconclusive"
    end

    ComparisonResult.new(
      score: score,
      status: status,
      ssim: ssim.round(4),
      dhash_distance: dhash_distance,
      mad: mad.round(2)
    )
  end
end
