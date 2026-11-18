# frozen_string_literal: true

class ZapSlot < ApplicationRecord
  SCHEDULE_KINDS = %w[daily once interval].freeze
  PATTERN_KINDS = %w[single roulette burst].freeze

  MIN_DURATION = 1
  MAX_DURATION = 5
  MIN_INTENSITY = 1
  MAX_INTENSITY = 100
  MIN_COUNT = 2
  MAX_COUNT = 8
  MIN_INTERVAL_MINUTES = 5
  MAX_INTERVAL_MINUTES = 720
  MIN_GAP_SECONDS = 2
  MAX_GAP_SECONDS = 5
  DEFAULT_GAP_SECONDS = 2
  ROULETTE_PAUSE_MIN = 2
  ROULETTE_PAUSE_MAX = 12

  belongs_to :zap_program, inverse_of: :zap_slots

  validates :schedule_kind, inclusion: { in: SCHEDULE_KINDS }
  validates :pattern_kind, inclusion: { in: PATTERN_KINDS }
  validates :duration, numericality: {
    only_integer: true,
    greater_than_or_equal_to: MIN_DURATION,
    less_than_or_equal_to: MAX_DURATION
  }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :schedule_fields_valid
  validate :pattern_fields_valid
  validate :program_slot_cap, on: :create

  before_validation :normalize_fields

  def due?(at: Time.current)
    tz = zap_program.beta.time_zone_object
    local = at.in_time_zone(tz)

    case schedule_kind
    when "daily"
      return false if last_fired_on == local.to_date

      local_minutes(local) == time_of_day_minutes
    when "once"
      return false if fired_at.present?
      return false if fires_at.blank?

      fires_local = fires_at.in_time_zone(tz)
      local.to_date == fires_local.to_date &&
        local.hour == fires_local.hour &&
        local.min == fires_local.min
    when "interval"
      return false unless within_window?(local)
      return true if last_fired_at.blank?

      (at - last_fired_at) >= interval_minutes.minutes
    else
      false
    end
  end

  def mark_fired!(at: Time.current)
    tz = zap_program.beta.time_zone_object
    local = at.in_time_zone(tz)

    attrs = { last_fired_at: at }
    case schedule_kind
    when "daily"
      attrs[:last_fired_on] = local.to_date
    when "once"
      attrs[:fired_at] = at
    end
    update!(attrs)
  end

  def once_done?
    schedule_kind == "once" && fired_at.present?
  end

  def build_shocks
    case pattern_kind
    when "single"
      [ { intensity: intensity, duration: duration, delay_seconds: 0 } ]
    when "roulette"
      count.times.map do |index|
        {
          intensity: rand(intensity_min..intensity_max),
          duration: duration,
          delay_seconds: index.zero? ? 0 : rand(ROULETTE_PAUSE_MIN..ROULETTE_PAUSE_MAX)
        }
      end
    when "burst"
      gap = gap_seconds.presence || DEFAULT_GAP_SECONDS
      count.times.map do |index|
        {
          intensity: intensity,
          duration: duration,
          delay_seconds: index.zero? ? 0 : gap
        }
      end
    else
      []
    end
  end

  def estimated_busy_seconds
    case pattern_kind
    when "single"
      duration + 2
    when "roulette"
      count * (ROULETTE_PAUSE_MAX + duration) + 2
    when "burst"
      gap = gap_seconds.presence || DEFAULT_GAP_SECONDS
      count * (gap + duration) + 2
    else
      duration + 2
    end
  end

  def notify_intensity
    case pattern_kind
    when "roulette"
      intensity_max
    else
      intensity
    end
  end

  def notify_duration
    duration
  end

  def summary_key_parts
    {
      schedule_kind: schedule_kind,
      pattern_kind: pattern_kind,
      time_of_day_minutes: time_of_day_minutes,
      fires_at: fires_at,
      interval_minutes: interval_minutes,
      window_start_minutes: window_start_minutes,
      window_end_minutes: window_end_minutes,
      intensity: intensity,
      intensity_min: intensity_min,
      intensity_max: intensity_max,
      duration: duration,
      count: count,
      gap_seconds: gap_seconds
    }
  end

  private

  def local_minutes(local)
    (local.hour * 60) + local.min
  end

  def within_window?(local)
    return true if window_start_minutes.blank? || window_end_minutes.blank?

    mins = local_minutes(local)
    if window_start_minutes <= window_end_minutes
      mins >= window_start_minutes && mins <= window_end_minutes
    else
      mins >= window_start_minutes || mins <= window_end_minutes
    end
  end

  def normalize_fields
    self.schedule_kind = schedule_kind.to_s
    self.pattern_kind = pattern_kind.to_s
    self.gap_seconds = DEFAULT_GAP_SECONDS if pattern_kind == "burst" && gap_seconds.blank?

    case schedule_kind
    when "daily"
      self.fires_at = nil
      self.interval_minutes = nil
      self.window_start_minutes = nil
      self.window_end_minutes = nil
    when "once"
      self.time_of_day_minutes = nil
      self.interval_minutes = nil
      self.window_start_minutes = nil
      self.window_end_minutes = nil
    when "interval"
      self.time_of_day_minutes = nil
      self.fires_at = nil
    end

    case pattern_kind
    when "single"
      self.intensity_min = nil
      self.intensity_max = nil
      self.count = nil
      self.gap_seconds = nil
    when "roulette"
      self.intensity = nil
      self.gap_seconds = nil
    when "burst"
      self.intensity_min = nil
      self.intensity_max = nil
    end
  end

  def schedule_fields_valid
    case schedule_kind
    when "daily"
      unless time_of_day_minutes.is_a?(Integer) && time_of_day_minutes.between?(0, 23 * 60 + 59)
        errors.add(:time_of_day_minutes, :invalid)
      end
    when "once"
      errors.add(:fires_at, :blank) if fires_at.blank?
    when "interval"
      unless interval_minutes.is_a?(Integer) &&
          interval_minutes.between?(MIN_INTERVAL_MINUTES, MAX_INTERVAL_MINUTES)
        errors.add(:interval_minutes, :invalid)
      end
      if window_start_minutes.present? ^ window_end_minutes.present?
        errors.add(:window_start_minutes, :invalid)
      end
      if window_start_minutes.present? && !window_start_minutes.between?(0, 23 * 60 + 59)
        errors.add(:window_start_minutes, :invalid)
      end
      if window_end_minutes.present? && !window_end_minutes.between?(0, 23 * 60 + 59)
        errors.add(:window_end_minutes, :invalid)
      end
    end
  end

  def pattern_fields_valid
    case pattern_kind
    when "single"
      unless intensity.is_a?(Integer) && intensity.between?(MIN_INTENSITY, MAX_INTENSITY)
        errors.add(:intensity, :invalid)
      end
    when "roulette"
      unless count.is_a?(Integer) && count.between?(MIN_COUNT, MAX_COUNT)
        errors.add(:count, :invalid)
      end
      unless intensity_min.is_a?(Integer) && intensity_min.between?(MIN_INTENSITY, MAX_INTENSITY)
        errors.add(:intensity_min, :invalid)
      end
      unless intensity_max.is_a?(Integer) && intensity_max.between?(MIN_INTENSITY, MAX_INTENSITY)
        errors.add(:intensity_max, :invalid)
      end
      if intensity_min.is_a?(Integer) && intensity_max.is_a?(Integer) && intensity_min > intensity_max
        errors.add(:intensity_min, :invalid)
      end
    when "burst"
      unless intensity.is_a?(Integer) && intensity.between?(MIN_INTENSITY, MAX_INTENSITY)
        errors.add(:intensity, :invalid)
      end
      unless count.is_a?(Integer) && count.between?(MIN_COUNT, MAX_COUNT)
        errors.add(:count, :invalid)
      end
      unless gap_seconds.is_a?(Integer) && gap_seconds.between?(MIN_GAP_SECONDS, MAX_GAP_SECONDS)
        errors.add(:gap_seconds, :invalid)
      end
    end
  end

  def program_slot_cap
    return if zap_program.blank?
    return unless zap_program.zap_slots.where.not(id: id).count >= ZapProgram::MAX_SLOTS

    errors.add(:base, I18n.t("zap_program.flash.slots_full"))
  end
end
