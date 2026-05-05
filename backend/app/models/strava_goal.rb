# frozen_string_literal: true

class StravaGoal < ApplicationRecord
  MAX_SECONDS = 86_400 * 365
  MIN_WINDOW_DAYS = 1
  MAX_WINDOW_DAYS = 365

  belongs_to :user
  has_many :strava_goal_checks, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :required_activity_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :window_days, numericality: {
    only_integer: true,
    greater_than_or_equal_to: MIN_WINDOW_DAYS,
    less_than_or_equal_to: MAX_WINDOW_DAYS
  }
  validates :check_time_minutes, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than: 24.hours / 60
  }
  validates :time_zone, presence: true
  validates :min_duration_seconds, allow_nil: true,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SECONDS }
  validates :min_calories, allow_nil: true,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :chaster_penalty_seconds,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SECONDS }
  validate :criteria_present
  validate :activity_types_are_strings
  validate :device_names_are_strings
  validate :time_zone_known

  scope :enabled, -> { where(enabled: true) }
  scope :recent, -> { order(created_at: :desc) }

  def activity_types=(value)
    super(normalize_list(value))
  end

  def device_names=(value)
    super(normalize_list(value))
  end

  def criteria_summary
    parts = []
    parts << "durée >= #{min_duration_seconds / 60} min" if min_duration_seconds.present?
    parts << "calories >= #{min_calories}" if min_calories.present?
    parts << "types: #{activity_types.join(', ')}" if activity_types.present?
    parts << "appareils: #{device_names.join(', ')}" if device_names.present?
    parts.join(" · ")
  end

  def required_count
    required_activity_count
  end

  def required_count=(value)
    self.required_activity_count = value
  end

  def window_label
    case window_days
    when 1 then "quotidien"
    when 7 then "hebdomadaire"
    else "#{window_days} jours glissants"
    end
  end

  def check_time_label
    "%02d:%02d" % check_time_parts
  end

  def check_time_parts
    [ check_time_minutes.to_i / 60, check_time_minutes.to_i % 60 ]
  end

  def time_zone_object
    ActiveSupport::TimeZone[time_zone] || Time.zone
  end

  def next_due_at(reference_time = Time.current)
    zone = time_zone_object
    local_now = reference_time.in_time_zone(zone)
    hour, minute = check_time_parts
    candidate = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
    candidate += 1.day if candidate <= local_now
    candidate
  end

  def previous_due_at(reference_time = Time.current)
    zone = time_zone_object
    local_now = reference_time.in_time_zone(zone)
    hour, minute = check_time_parts
    candidate = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
    candidate -= 1.day if candidate > local_now
    candidate
  end

  def due_at_or_before(reference_time = Time.current)
    zone = time_zone_object
    local_now = reference_time.in_time_zone(zone)
    hour, minute = check_time_parts
    due_at = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
    return nil if due_at > reference_time
    return nil if last_check_due_at.present? && last_check_due_at >= due_at

    due_at
  end

  def due_at?(reference_time = Time.current)
    due_at_or_before(reference_time).present?
  end

  def period_start_for(due_at)
    due_at - window_days.days
  end

  private

  def normalize_list(value)
    list = case value
    when String
      value.split(/[\n,;]/)
    when Array
      value
    else
      []
    end

    list.map { |item| item.to_s.strip }.reject(&:blank?).uniq
  end

  def criteria_present
    return if min_duration_seconds.present? || min_calories.present? || activity_types.present? || device_names.present?

    errors.add(:base, "Ajoute au moins un critère Strava.")
  end

  def activity_types_are_strings
    errors.add(:activity_types, "doit être une liste") unless activity_types.is_a?(Array)
  end

  def device_names_are_strings
    errors.add(:device_names, "doit être une liste") unless device_names.is_a?(Array)
  end

  def time_zone_known
    return if time_zone.blank? || ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "est invalide")
  end
end
