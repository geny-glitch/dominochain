# frozen_string_literal: true

class WallpaperSanction
  LEGACY_ACTIONS = %w[none chaster_add_time chaster_freeze pishock].freeze

  attr_reader :chaster_add_time_enabled, :chaster_seconds, :chaster_freeze_enabled,
              :pishock_enabled, :pishock_intensity, :pishock_duration

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
    new(
      chaster_add_time_enabled: cast_bool(hash["chaster_add_time_enabled"]),
      chaster_seconds: hash["chaster_seconds"],
      chaster_freeze_enabled: cast_bool(hash["chaster_freeze_enabled"]),
      pishock_enabled: cast_bool(hash["pishock_enabled"]),
      pishock_intensity: hash["pishock_intensity"],
      pishock_duration: hash["pishock_duration"]
    )
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
    pishock_duration: 1
  )
    @chaster_add_time_enabled = self.class.cast_bool(chaster_add_time_enabled)
    @chaster_freeze_enabled = self.class.cast_bool(chaster_freeze_enabled)
    @pishock_enabled = self.class.cast_bool(pishock_enabled)
    @chaster_seconds = normalize_chaster_seconds(chaster_seconds)
    @pishock_intensity = pishock_intensity.to_i.clamp(1, 100)
    @pishock_duration = pishock_duration.to_i.clamp(1, 15)
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

  def any_active?
    chaster_add_time_active? || chaster_freeze_active? || pishock_active?
  end

  # Legacy compatibility for callers that still read a single action.
  def action
    return "chaster_add_time" if chaster_add_time_active?
    return "chaster_freeze" if chaster_freeze_active?
    return "pishock" if pishock_active?

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
      "pishock_duration" => pishock_duration
    }
  end

  private

  def normalize_chaster_seconds(value)
    return nil if value.blank?

    value.to_i.clamp(1, 86_400 * 365)
  end
end
