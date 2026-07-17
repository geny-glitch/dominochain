# frozen_string_literal: true

class WallpaperSanction
  LEGACY_ACTIONS = %w[none chaster_add_time chaster_freeze pishock].freeze
  TARGET_MODES = %w[specific random].freeze

  attr_reader :chaster_add_time_enabled, :chaster_seconds, :chaster_freeze_enabled,
              :pishock_enabled, :pishock_intensity, :pishock_duration,
              :leverage_photo_lock_enabled, :leverage_photo_lock_seconds,
              :leverage_photo_lock_target_mode, :leverage_photo_lock_photo_id,
              :leverage_photo_delete_enabled, :leverage_photo_delete_target_mode,
              :leverage_photo_delete_photo_id

  def self.from_hash(value)
    hash = value.is_a?(Hash) ? value.stringify_keys : {}
    if hash.key?("action")
      from_legacy_hash(hash)
    else
      from_modern_hash(hash)
    end
  end

  def self.from_legacy_hash(hash)
    action = hash["action"].to_s
    new(
      chaster_add_time_enabled: action == "chaster_add_time",
      chaster_seconds: hash["chaster_seconds"],
      chaster_freeze_enabled: action == "chaster_freeze",
      pishock_enabled: action == "pishock",
      pishock_intensity: hash["pishock_intensity"],
      pishock_duration: hash["pishock_duration"]
    )
  end

  def self.from_modern_hash(hash)
    lock = coalesce_lock_fields(hash)
    new(
      chaster_add_time_enabled: cast_bool(hash["chaster_add_time_enabled"]),
      chaster_seconds: hash["chaster_seconds"],
      chaster_freeze_enabled: cast_bool(hash["chaster_freeze_enabled"]),
      pishock_enabled: cast_bool(hash["pishock_enabled"]),
      pishock_intensity: hash["pishock_intensity"],
      pishock_duration: hash["pishock_duration"],
      leverage_photo_lock_enabled: lock[:enabled],
      leverage_photo_lock_seconds: lock[:seconds],
      leverage_photo_lock_target_mode: lock[:target_mode],
      leverage_photo_lock_photo_id: lock[:photo_id],
      leverage_photo_delete_enabled: cast_bool(hash["leverage_photo_delete_enabled"]),
      leverage_photo_delete_target_mode: hash["leverage_photo_delete_target_mode"],
      leverage_photo_delete_photo_id: hash["leverage_photo_delete_photo_id"]
    )
  end

  # Prefer unified lock_* keys; fall back to legacy start/add_time (start wins if both).
  def self.coalesce_lock_fields(hash)
    if hash.key?("leverage_photo_lock_enabled") || hash.key?("leverage_photo_lock_seconds")
      return {
        enabled: cast_bool(hash["leverage_photo_lock_enabled"]),
        seconds: hash["leverage_photo_lock_seconds"],
        target_mode: hash["leverage_photo_lock_target_mode"],
        photo_id: hash["leverage_photo_lock_photo_id"]
      }
    end

    start_enabled = cast_bool(hash["leverage_photo_start_enabled"])
    add_enabled = cast_bool(hash["leverage_photo_add_time_enabled"])
    if start_enabled
      {
        enabled: true,
        seconds: hash["leverage_photo_start_seconds"],
        target_mode: hash["leverage_photo_start_target_mode"],
        photo_id: hash["leverage_photo_start_photo_id"]
      }
    elsif add_enabled
      {
        enabled: true,
        seconds: hash["leverage_photo_add_time_seconds"],
        target_mode: hash["leverage_photo_add_time_target_mode"],
        photo_id: hash["leverage_photo_add_time_photo_id"]
      }
    else
      {
        enabled: false,
        seconds: nil,
        target_mode: "random",
        photo_id: nil
      }
    end
  end

  def self.cast_bool(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def initialize(
    chaster_add_time_enabled: false,
    chaster_seconds: nil,
    chaster_freeze_enabled: false,
    pishock_enabled: false,
    pishock_intensity: 50,
    pishock_duration: 1,
    leverage_photo_lock_enabled: false,
    leverage_photo_lock_seconds: nil,
    leverage_photo_lock_target_mode: "random",
    leverage_photo_lock_photo_id: nil,
    leverage_photo_delete_enabled: false,
    leverage_photo_delete_target_mode: "random",
    leverage_photo_delete_photo_id: nil
  )
    @chaster_add_time_enabled = self.class.cast_bool(chaster_add_time_enabled)
    @chaster_freeze_enabled = self.class.cast_bool(chaster_freeze_enabled)
    @pishock_enabled = self.class.cast_bool(pishock_enabled)
    @chaster_seconds = normalize_chaster_seconds(chaster_seconds)
    @pishock_intensity = pishock_intensity.to_i.clamp(1, 100)
    @pishock_duration = pishock_duration.to_i.clamp(1, 15)

    @leverage_photo_lock_enabled = self.class.cast_bool(leverage_photo_lock_enabled)
    @leverage_photo_lock_seconds = normalize_leverage_seconds(leverage_photo_lock_seconds)
    @leverage_photo_lock_target_mode = normalize_target_mode(leverage_photo_lock_target_mode)
    @leverage_photo_lock_photo_id = normalize_photo_id(leverage_photo_lock_photo_id)

    @leverage_photo_delete_enabled = self.class.cast_bool(leverage_photo_delete_enabled)
    @leverage_photo_delete_target_mode = normalize_target_mode(leverage_photo_delete_target_mode)
    @leverage_photo_delete_photo_id = normalize_photo_id(leverage_photo_delete_photo_id)
  end

  def chaster_add_time_active?
    chaster_add_time_enabled && chaster_seconds.to_i.positive?
  end

  def chaster_freeze_active?
    chaster_freeze_enabled
  end

  def pishock_active?
    pishock_enabled
  end

  def leverage_photo_lock_active?
    leverage_photo_lock_enabled && leverage_photo_lock_seconds.to_i.positive?
  end

  def leverage_photo_delete_active?
    leverage_photo_delete_enabled
  end

  def any_active?
    chaster_add_time_active? || chaster_freeze_active? || pishock_active? ||
      leverage_photo_lock_active? || leverage_photo_delete_active?
  end

  # Legacy compatibility for callers that still read a single action.
  def action
    return "chaster_add_time" if chaster_add_time_active?
    return "chaster_freeze" if chaster_freeze_active?
    return "pishock" if pishock_active?
    return "leverage_photo_lock" if leverage_photo_lock_active?
    return "leverage_photo_delete" if leverage_photo_delete_active?

    "none"
  end

  def active?
    any_active?
  end

  def to_h
    {
      "chaster_add_time_enabled" => chaster_add_time_enabled,
      "chaster_seconds" => chaster_add_time_enabled ? chaster_seconds : nil,
      "chaster_freeze_enabled" => chaster_freeze_enabled,
      "pishock_enabled" => pishock_enabled,
      "pishock_intensity" => pishock_intensity,
      "pishock_duration" => pishock_duration,
      "leverage_photo_lock_enabled" => leverage_photo_lock_enabled,
      "leverage_photo_lock_seconds" => leverage_photo_lock_enabled ? leverage_photo_lock_seconds : nil,
      "leverage_photo_lock_target_mode" => leverage_photo_lock_target_mode,
      "leverage_photo_lock_photo_id" => leverage_photo_lock_enabled && leverage_photo_lock_target_mode == "specific" ? leverage_photo_lock_photo_id : nil,
      "leverage_photo_delete_enabled" => leverage_photo_delete_enabled,
      "leverage_photo_delete_target_mode" => leverage_photo_delete_target_mode,
      "leverage_photo_delete_photo_id" => leverage_photo_delete_enabled && leverage_photo_delete_target_mode == "specific" ? leverage_photo_delete_photo_id : nil
    }
  end

  private

  def normalize_chaster_seconds(value)
    return nil if value.blank?

    value.to_i.clamp(1, 86_400 * 365)
  end

  def normalize_leverage_seconds(value)
    return nil if value.blank?

    value.to_i.clamp(LeveragePhoto::MIN_DURATION_SECONDS, LeveragePhoto::MAX_DURATION_SECONDS)
  end

  def normalize_target_mode(value)
    mode = value.to_s
    TARGET_MODES.include?(mode) ? mode : "random"
  end

  def normalize_photo_id(value)
    return nil if value.blank?

    id = value.to_i
    id.positive? ? id : nil
  end
end
