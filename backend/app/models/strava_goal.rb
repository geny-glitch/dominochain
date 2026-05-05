# frozen_string_literal: true

class StravaGoal < ApplicationRecord
  MAX_SECONDS = 86_400 * 365

  belongs_to :user
  has_many :strava_goal_checks, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :weekly_required_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :min_duration_seconds, allow_nil: true,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SECONDS }
  validates :min_calories, allow_nil: true,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :chaster_penalty_seconds,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SECONDS }
  validate :criteria_present
  validate :activity_types_are_strings
  validate :device_names_are_strings

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
end
