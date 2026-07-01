# frozen_string_literal: true

require "vips"

class WallpaperScreenshotComparator
  ComparisonResult = Struct.new(
    :score, :status, :ssim, :dhash_distance, :mad,
    :cells_compared, :cells_skipped,
    keyword_init: true
  )

  COMPARE_SIZE = 64
  # Cap longest side during comparison so Vips stays within the worker VM RAM budget.
  WORKING_MAX_SIDE = 960
  TOP_MARGIN_RATIO = 0.08
  BOTTOM_MARGIN_RATIO = 0.05
  GRID_COLS = 4
  GRID_ROWS = 6
  EDGE_DENSITY_THRESHOLD = 28.0
  CLOCK_ZONE_ROW_RATIO = 0.22
  CLOCK_ZONE_COL_START_RATIO = 0.25
  CLOCK_ZONE_COL_END_RATIO = 0.75

  def initialize(wallpaper:, device:, timer: nil, screenshot:)
    @screenshot = screenshot
    @wallpaper = wallpaper
    @device = device
    @timer = timer
  end

  def compare
    captured_image = measure(:load_screenshot) { load_attachment(@screenshot.image) }
    reference_image = measure(:load_wallpaper) { load_wallpaper_reference }

    grid_metrics = measure(:compare_grid) { grid_metrics_for(captured_image, reference_image) }
    classify(**grid_metrics)
  end

  def metrics_for(captured_image, reference_image, edges_only: false)
    captured_norm = normalize_legacy(captured_image, edges_only: edges_only)
    reference_norm = normalize_legacy(reference_image, edges_only: edges_only)

    ssim = compute_ssim(captured_norm, reference_norm)
    dhash_distance = hamming_distance(
      compute_dhash(captured_norm),
      compute_dhash(reference_norm)
    )
    mad = mean_absolute_difference(captured_norm, reference_norm)
    score = composite_score(ssim, dhash_distance, mad)

    { ssim: ssim, dhash_distance: dhash_distance, mad: mad, score: score }
  end

  private

  def measure(step, &block)
    if @timer
      @timer.measure(step, &block)
    else
      yield
    end
  end

  def load_attachment(attachment)
    ImagePreviewVariant.open_processed_preview(attachment.blob) do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)
      materialize_image(downscale_if_large(image))
    end
  end

  def load_wallpaper_reference
    ImagePreviewVariant.open_processed_preview(@wallpaper.image.blob) do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)
      materialize_image(downscale_if_large(image))
    end
  end

  def materialize_image(image)
    data = image.write_to_memory
    Vips::Image.new_from_memory(data, image.width, image.height, image.bands, :uchar)
  end

  def downscale_if_large(image)
    longest = [image.width, image.height].max
    return image if longest <= WORKING_MAX_SIDE

    scale = WORKING_MAX_SIDE.to_f / longest
    image.resize(scale, vscale: scale)
  end

  def grid_metrics_for(captured_image, reference_image)
    captured_prep = preprocess_for_grid(captured_image)
    reference_prep = resize_to_match(preprocess_for_grid(reference_image), captured_prep)

    width = captured_prep.width
    height = captured_prep.height
    cell_w = width / GRID_COLS
    cell_h = height / GRID_ROWS

    score_pairs = []
    ssim_pairs = []
    dhash_pairs = []
    mad_pairs = []
    cells_compared = 0
    cells_skipped = 0

    GRID_ROWS.times do |row|
      GRID_COLS.times do |col|
        if fixed_ui_mask?(row, col)
          cells_skipped += 1
          next
        end

        x = col * cell_w
        y = row * cell_h
        captured_cell = captured_prep.crop(x, y, cell_w, cell_h)
        reference_cell = reference_prep.crop(x, y, cell_w, cell_h)

        if ui_cell?(captured_cell)
          cells_skipped += 1
          next
        end

        captured_norm = normalize_cell(captured_cell)
        reference_norm = normalize_cell(reference_cell)

        ssim = compute_ssim(captured_norm, reference_norm)
        dhash_distance = hamming_distance(
          compute_dhash(captured_norm),
          compute_dhash(reference_norm)
        )
        mad = mean_absolute_difference(captured_norm, reference_norm)
        score = composite_score(ssim, dhash_distance, mad)
        weight = cell_w * cell_h

        score_pairs << [score, weight]
        ssim_pairs << [ssim, weight]
        dhash_pairs << [dhash_distance, weight]
        mad_pairs << [mad, weight]
        cells_compared += 1
      end
    end

    if cells_compared.zero?
      fallback = metrics_for(captured_image, reference_image)
      return fallback.merge(cells_compared: 0, cells_skipped: cells_skipped)
    end

    {
      score: weighted_median(score_pairs).round(3),
      ssim: weighted_mean(ssim_pairs),
      dhash_distance: weighted_mean(dhash_pairs).round,
      mad: weighted_mean(mad_pairs),
      cells_compared: cells_compared,
      cells_skipped: cells_skipped
    }
  end

  def preprocess_for_grid(image)
    aligned = center_crop_to_device_aspect(crop_margins(image))
    working = downscale_if_large(aligned)
    materialize_image(working.gaussblur(1.5).colourspace("b-w"))
  end

  def center_crop_to_device_aspect(image)
    target_width = (@device.screen_width.presence || image.width).to_f
    target_height = (@device.screen_height.presence || image.height).to_f
    return image if target_width <= 0 || target_height <= 0

    target_aspect = target_width / target_height
    image_aspect = image.width.to_f / image.height

    if image_aspect > target_aspect
      new_width = (image.height * target_aspect).round
      new_width = [new_width, 1].max
      left = [(image.width - new_width) / 2, 0].max
      image.crop(left, 0, new_width, image.height)
    elsif image_aspect < target_aspect
      new_height = (image.width / target_aspect).round
      new_height = [new_height, 1].max
      top = [(image.height - new_height) / 2, 0].max
      image.crop(0, top, image.width, new_height)
    else
      image
    end
  end

  def normalize_cell(cell)
    scale = COMPARE_SIZE.to_f / [cell.width, cell.height].max
    materialize_image(cell.resize(scale, vscale: scale))
  end

  def resize_to_match(image, target)
    return image if image.width == target.width && image.height == target.height

    materialize_image(
      image.resize(
        target.width.to_f / image.width,
        vscale: target.height.to_f / image.height
      )
    )
  end

  def fixed_ui_mask?(row, col)
    clock_rows = 0..[(GRID_ROWS * CLOCK_ZONE_ROW_RATIO).floor - 1, 0].max
    col_start = (GRID_COLS * CLOCK_ZONE_COL_START_RATIO).floor
    col_end = [(GRID_COLS * CLOCK_ZONE_COL_END_RATIO).ceil - 1, GRID_COLS - 1].min
    clock_cols = col_start..col_end

    clock_rows.cover?(row) && clock_cols.cover?(col)
  end

  def ui_cell?(cell)
    cell.deviate > EDGE_DENSITY_THRESHOLD
  end

  def weighted_median(pairs)
    sorted = pairs.sort_by { |value, _weight| value }
    total_weight = pairs.sum { |_value, weight| weight }
    half = total_weight / 2.0
    cumulative = 0.0

    sorted.each do |value, weight|
      cumulative += weight
      return value if cumulative >= half
    end

    sorted.last.first
  end

  def weighted_mean(pairs)
    total_weight = pairs.sum { |_value, weight| weight }
    return 0.0 if total_weight.zero?

    pairs.sum { |value, weight| value * weight } / total_weight
  end

  # Legacy path kept for unit tests and grid fallback.
  def normalize_legacy(image, edges_only: false)
    cropped = crop_margins(image)
    cropped = crop_edges(cropped) if edges_only
    fitted = center_crop_to_device_aspect(cropped)
    blurred = fitted.gaussblur(1.5)
    grey = blurred.colourspace("b-w")
    scale = COMPARE_SIZE.to_f / [grey.width, grey.height].max
    materialize_image(grey.resize(scale, vscale: scale))
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

  def classify(ssim:, dhash_distance:, mad:, score: nil, cells_compared: nil, cells_skipped: nil)
    ssim_threshold = ENV.fetch("WALLPAPER_SSIM_THRESHOLD", "0.75").to_f
    dhash_threshold = ENV.fetch("WALLPAPER_DHASH_THRESHOLD", "15").to_i
    score_threshold = ENV.fetch("WALLPAPER_SCORE_THRESHOLD", "0.65").to_f
    score_dhash_max = ENV.fetch("WALLPAPER_SCORE_DHASH_MAX", "18").to_i
    score_mad_max = ENV.fetch("WALLPAPER_SCORE_MAD_MAX", "35").to_f
    overlay_score_threshold = ENV.fetch("WALLPAPER_OVERLAY_SCORE_THRESHOLD", "0.48").to_f
    overlay_ssim_min = ENV.fetch("WALLPAPER_OVERLAY_SSIM_MIN", "0.1").to_f
    mismatch_ssim = ENV.fetch("WALLPAPER_MISMATCH_SSIM", "0.5").to_f
    mismatch_dhash = ENV.fetch("WALLPAPER_MISMATCH_DHASH", "20").to_i
    mad_match_threshold = ENV.fetch("WALLPAPER_MAD_MATCH_THRESHOLD", "35").to_f
    mad_mismatch_threshold = ENV.fetch("WALLPAPER_MAD_MISMATCH_THRESHOLD", "45").to_f

    score = score || composite_score(ssim, dhash_distance, mad)
    clearly_mismatch = mismatch?(
      score:, ssim:, dhash_distance:, mad:,
      overlay_score_threshold:, overlay_ssim_min:, mismatch_ssim:, mismatch_dhash:, mad_mismatch_threshold:
    )
    dhash_match = dhash_distance <= dhash_threshold && mad <= mad_match_threshold
    score_match = score >= score_threshold &&
                  dhash_distance <= score_dhash_max &&
                  mad <= score_mad_max
    overlay_match = score >= overlay_score_threshold && !clearly_mismatch

    status = if ssim >= ssim_threshold || dhash_match || score_match || overlay_match ||
                  mad <= (mad_match_threshold / 2.0)
      "verified"
    else
      "mismatch"
    end

    ComparisonResult.new(
      score: score,
      status: status,
      ssim: ssim.round(4),
      dhash_distance: dhash_distance,
      mad: mad.round(2),
      cells_compared: cells_compared,
      cells_skipped: cells_skipped
    )
  end

  def mismatch?(score:, ssim:, dhash_distance:, mad:, overlay_score_threshold:, overlay_ssim_min:, mismatch_ssim:, mismatch_dhash:, mad_mismatch_threshold:)
    if score >= overlay_score_threshold
      return true if ssim < overlay_ssim_min

      return false
    end

    return true if mad > (mad_mismatch_threshold * 1.5)

    ssim < mismatch_ssim && dhash_distance > mismatch_dhash && mad > mad_mismatch_threshold
  end
end
