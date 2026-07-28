# frozen_string_literal: true

class PuzzleSessionCreator
  Result = Struct.new(:ok, :session, :error, :http_status, keyword_init: true)

  def initialize(
    user:,
    origin: "self",
    image_source: nil,
    piece_count: nil,
    reference_mode: nil,
    time_limit_seconds: nil,
    leverage_photo_id: nil,
    wallpaper_id: nil,
    target_mode: "random",
    photo_id: nil,
    upload_image: nil,
    notify: false
  )
    @user = user
    @origin = origin.to_s
    @image_source = image_source.to_s.presence
    @piece_count = piece_count
    @reference_mode = reference_mode
    @time_limit_seconds = time_limit_seconds
    @leverage_photo_id = leverage_photo_id.presence || photo_id
    @wallpaper_id = wallpaper_id
    @target_mode = target_mode.to_s
    @upload_image = upload_image
    @notify = notify
  end

  def call
    unless BetaCatalog.new(@user).source_enabled?("puzzle")
      return Result.new(ok: false, error: :source_disabled, http_status: :unprocessable_entity)
    end

    config = @user.ensure_puzzle_config!

    if @origin == "self"
      cooldown_error = enforce_cooldown!(config)
      return cooldown_error if cooldown_error
    end

    image_source = resolve_image_source
    return Result.new(ok: false, error: :invalid_image_source, http_status: :unprocessable_entity) if image_source.blank?

    leverage_photo, wallpaper = resolve_image_targets(image_source)
    if image_source == "leverage_photo" && leverage_photo.nil?
      return Result.new(ok: false, error: :no_eligible_photo, http_status: :unprocessable_entity)
    end
    if image_source == "wallpaper" && wallpaper.nil?
      return Result.new(ok: false, error: :no_wallpaper, http_status: :unprocessable_entity)
    end
    if image_source == "upload" && @upload_image.blank?
      return Result.new(ok: false, error: :missing_upload, http_status: :unprocessable_entity)
    end

    piece_count = PuzzleConfig.clamp_piece_count(@piece_count.presence || config.default_piece_count)
    cols, rows = PuzzleConfig.grid_for_piece_count(piece_count)
    reference_mode = (@reference_mode.presence || config.default_reference_mode).to_s
    reference_mode = "blurred" unless PuzzleConfig::REFERENCE_MODES.include?(reference_mode)

    time_limit = normalize_time_limit(@time_limit_seconds)
    time_limit = config.default_time_limit_seconds if @time_limit_seconds.nil? && @origin == "self"

    session = @user.puzzle_sessions.create!(
      status: "assigned",
      origin: @origin,
      image_source: image_source,
      leverage_photo: leverage_photo,
      wallpaper: wallpaper,
      piece_count: piece_count,
      grid_cols: cols,
      grid_rows: rows,
      pieces_total: piece_count,
      pieces_placed: 0,
      reference_mode: reference_mode,
      time_limit_seconds: time_limit,
      layout_seed: SecureRandom.random_number(1 << 31),
      config_snapshot: {
        "image_source" => image_source,
        "piece_count" => piece_count,
        "reference_mode" => reference_mode,
        "time_limit_seconds" => time_limit,
        "origin" => @origin
      }
    )

    if image_source == "upload" && @upload_image.present?
      session.upload_image.attach(@upload_image)
      session.save!
    end

    notify_devices!(session) if @notify

    Result.new(ok: true, session: session)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(ok: false, error: e.record.errors.full_messages.join(", "), http_status: :unprocessable_entity)
  end

  private

  def enforce_cooldown!(config)
    return nil if config.cooldown_seconds.to_i <= 0

    last = @user.puzzle_sessions.where(origin: "self").where.not(status: "assigned").order(created_at: :desc).first
    return nil if last.nil?

    elapsed = Time.current - last.created_at
    remaining = config.cooldown_seconds - elapsed.to_i
    return nil if remaining <= 0

    Result.new(ok: false, error: :cooldown, http_status: :unprocessable_entity)
  end

  def resolve_image_source
    source = @image_source.presence
    return source if PuzzleSession::IMAGE_SOURCES.include?(source)

    return "leverage_photo" if @leverage_photo_id.present?
    return "wallpaper" if @wallpaper_id.present?
    return "upload" if @upload_image.present?

    "leverage_photo"
  end

  def resolve_image_targets(image_source)
    case image_source
    when "leverage_photo"
      photo = if @leverage_photo_id.present?
        @user.leverage_photos.not_deleted.find_by(id: @leverage_photo_id)
      else
        LeveragePhotos::ResolveTarget.call(
          user: @user,
          action: :crop_to_progress,
          target_mode: @target_mode.presence || "random",
          photo_id: nil
        )
      end
      [photo, nil]
    when "wallpaper"
      wallpaper = if @wallpaper_id.present?
        Wallpaper.joins(:device).where(devices: { user_id: @user.id }).find_by(id: @wallpaper_id)
      else
        @user.primary_device&.current_wallpaper
      end
      [nil, wallpaper]
    else
      [nil, nil]
    end
  end

  def normalize_time_limit(raw)
    return nil if raw.blank?

    n = raw.to_i
    return nil if n <= 0

    n = [n, PuzzleConfig::MIN_TIME_LIMIT_SECONDS].max
    [n, PuzzleConfig::MAX_TIME_LIMIT_SECONDS].min
  end

  def notify_devices!(session)
    @user.devices.find_each do |device|
      FcmService.send_puzzle_assigned_notification(device: device, session: session)
    end
  rescue StandardError => e
    Rails.logger.warn("[PuzzleSessionCreator] notify failed: #{e.class}: #{e.message}")
  end
end
