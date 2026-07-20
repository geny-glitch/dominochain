# frozen_string_literal: true

class PuryfiConfig
  LABEL_IDS = (0..25).freeze
  SHOCK_LEVELS = (1..3).freeze

  DEFAULT_PISHOCK_LEVEL_SETTINGS = {
    "1" => { "intensity" => 10, "duration" => 1 },
    "2" => { "intensity" => 30, "duration" => 1 },
    "3" => { "intensity" => 60, "duration" => 1 }
  }.freeze

  class << self
    def shock_level_for_label(user, label_id)
      levels = user.puryfi_shock_level_per_label
      levels = {} unless levels.is_a?(Hash)
      raw = levels[label_id.to_s]
      raw.to_i.clamp(0, 3)
    end

    def pishock_level_settings_for(user)
      merged = DEFAULT_PISHOCK_LEVEL_SETTINGS.deep_dup
      raw = user.puryfi_pishock_level_settings
      return merged unless raw.is_a?(Hash)

      SHOCK_LEVELS.each do |level|
        key = level.to_s
        entry = raw[key] || raw[level]
        next unless entry.is_a?(Hash)

        intensity = entry["intensity"] || entry[:intensity]
        duration = entry["duration"] || entry[:duration]
        merged[key] ||= {}
        merged[key]["intensity"] = intensity.to_i.clamp(1, 100) if intensity.present?
        merged[key]["duration"] = duration.to_i.clamp(1, 15) if duration.present?
      end
      merged
    end

    def pishock_params_for_level(user, level)
      level = level.to_i.clamp(0, 3)
      return nil if level.zero?

      settings = pishock_level_settings_for(user)[level.to_s] || {}
      intensity = settings["intensity"].to_i
      duration = settings["duration"].to_i
      return nil unless intensity.positive? && duration.positive?

      {
        intensity: ShowcaseGameConfig.pishock_intensity(intensity, user),
        duration: duration.clamp(1, 15)
      }
    end

    def sanitize_shock_level_per_label(raw, existing:)
      merged = existing.stringify_keys
      h = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
      h = {} unless h.is_a?(Hash)

      LABEL_IDS.each do |i|
        key = i.to_s
        next unless h.key?(key) || h.key?(i)

        merged[key] = (h[key] || h[i]).to_i.clamp(0, 3)
      end
      merged
    end

    def sanitize_pishock_level_settings(raw, existing:)
      merged = DEFAULT_PISHOCK_LEVEL_SETTINGS.deep_dup
      base = existing.is_a?(Hash) ? existing : {}
      SHOCK_LEVELS.each do |level|
        key = level.to_s
        entry = base[key] || base[level]
        next unless entry.is_a?(Hash)

        intensity = entry["intensity"] || entry[:intensity]
        duration = entry["duration"] || entry[:duration]
        merged[key] ||= {}
        merged[key]["intensity"] = intensity.to_i.clamp(1, 100) if intensity.present?
        merged[key]["duration"] = duration.to_i.clamp(1, 15) if duration.present?
      end

      h = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
      h = {} unless h.is_a?(Hash)

      SHOCK_LEVELS.each do |level|
        key = level.to_s
        next unless h.key?(key) || h.key?(level)

        entry = h[key] || h[level]
        next unless entry.is_a?(Hash)

        merged[key] ||= {}
        if entry.key?("intensity") || entry.key?(:intensity)
          merged[key]["intensity"] = (entry["intensity"] || entry[:intensity]).to_i.clamp(1, 100)
        end
        if entry.key?("duration") || entry.key?(:duration)
          merged[key]["duration"] = (entry["duration"] || entry[:duration]).to_i.clamp(1, 15)
        end
      end
      merged
    end

    def pishock_payload_for_user(user)
      {
        puryfi_shock_level_per_label: user.puryfi_shock_level_per_label,
        puryfi_pishock_level_settings: pishock_level_settings_for(user)
      }
    end
  end
end
