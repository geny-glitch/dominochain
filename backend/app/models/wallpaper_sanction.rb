# frozen_string_literal: true

class WallpaperSanction
  ACTIONS = %w[none chaster_add_time chaster_freeze pishock].freeze

  attr_reader :action, :chaster_seconds, :pishock_intensity, :pishock_duration

  def self.from_hash(value)
    hash = value.is_a?(Hash) ? value.stringify_keys : {}
    new(
      action: hash["action"],
      chaster_seconds: hash["chaster_seconds"],
      pishock_intensity: hash["pishock_intensity"],
      pishock_duration: hash["pishock_duration"]
    )
  end

  def initialize(action: "none", chaster_seconds: 3600, pishock_intensity: 50, pishock_duration: 1)
    @action = ACTIONS.include?(action.to_s) ? action.to_s : "none"
    @chaster_seconds = chaster_seconds.to_i.clamp(1, 86_400 * 365)
    @pishock_intensity = pishock_intensity.to_i.clamp(1, 100)
    @pishock_duration = pishock_duration.to_i.clamp(1, 15)
  end

  def active?
    action != "none"
  end

  def to_h
    {
      "action" => action,
      "chaster_seconds" => chaster_seconds,
      "pishock_intensity" => pishock_intensity,
      "pishock_duration" => pishock_duration
    }
  end
end
