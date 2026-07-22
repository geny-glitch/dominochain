# frozen_string_literal: true

class ChessComGoal < ApplicationRecord
  RATING_TYPES = %w[blitz bullet rapid daily].freeze
  SCHEDULE_MODES = %w[deadline recurring].freeze
  RECURRENCE_KINDS = %w[daily interval].freeze
  MIN_RATING = 100
  MAX_RATING = 3500
  MIN_INTERVAL_MINUTES = 5
  MAX_INTERVAL_MINUTES = 7 * 24 * 60

  belongs_to :user
  has_many :chess_com_goal_checks, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :rating_type, inclusion: { in: RATING_TYPES }
  validates :schedule_mode, inclusion: { in: SCHEDULE_MODES }
  validates :recurrence_kind, inclusion: { in: RECURRENCE_KINDS }
  validates :target_rating, numericality: {
    only_integer: true,
    greater_than_or_equal_to: MIN_RATING,
    less_than_or_equal_to: MAX_RATING
  }
  validates :baseline_rating, allow_nil: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: MIN_RATING,
    less_than_or_equal_to: MAX_RATING
  }
  validates :deadline_at, presence: true
  validates :time_zone, presence: true
  validates :check_time_minutes, presence: true, if: :daily_recurring?
  validates :check_time_minutes, allow_nil: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than: 24.hours / 60
  }
  validates :interval_minutes, presence: true, if: :interval_recurring?
  validates :interval_minutes, allow_nil: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: MIN_INTERVAL_MINUTES,
    less_than_or_equal_to: MAX_INTERVAL_MINUTES
  }
  validate :time_zone_known
  validate :deadline_in_future, on: :create

  scope :enabled, -> { where(enabled: true) }
  scope :due_for_check, ->(_reference_time = Time.current) { enabled }
  scope :recent, -> { order(created_at: :desc) }

  def self.rating_type_options_for_select
    RATING_TYPES.map { |type| [ I18n.t("beta.chess.rating_types.#{type}"), type ] }
  end

  def self.schedule_mode_options_for_select
    SCHEDULE_MODES.map { |mode| [ I18n.t("beta.chess.schedule_modes.#{mode}"), mode ] }
  end

  def deadline_mode?
    schedule_mode == "deadline"
  end

  def recurring?
    schedule_mode == "recurring"
  end

  def daily_recurring?
    recurring? && recurrence_kind == "daily"
  end

  def interval_recurring?
    recurring? && recurrence_kind == "interval"
  end

  def achieved?
    last_check_status == "passed"
  end

  def time_zone_object
    ActiveSupport::TimeZone[time_zone] || Time.zone
  end

  def rating_type_label
    I18n.t("beta.chess.rating_types.#{rating_type}", default: rating_type.to_s.humanize)
  end

  def deadline_local
    deadline_at.in_time_zone(time_zone_object)
  end

  def check_time_label
    "%02d:%02d" % check_time_parts
  end

  def check_time_parts
    minutes = check_time_minutes.to_i
    [ minutes / 60, minutes % 60 ]
  end

  def interval_label
    minutes = interval_minutes.to_i
    if minutes >= 60 && (minutes % 60).zero?
      I18n.t("beta.chess.interval_hours", count: minutes / 60)
    else
      I18n.t("beta.chess.interval_minutes", count: minutes)
    end
  end

  def next_due_at(reference_time = Time.current)
    if interval_recurring?
      interval_next_due_at(reference_time)
    else
      daily_next_due_at(reference_time)
    end
  end

  def previous_due_at(reference_time = Time.current)
    if interval_recurring?
      interval_previous_due_at(reference_time)
    else
      daily_previous_due_at(reference_time)
    end
  end

  def due_at_or_before(reference_time = Time.current)
    if recurring?
      recurring_due_at_or_before(reference_time)
    else
      deadline_due_at_or_before(reference_time)
    end
  end

  def due_at?(reference_time = Time.current)
    due_at_or_before(reference_time).present?
  end

  def preview_check_due_at(reference_time = Time.current)
    due_at_or_before(reference_time) || fallback_preview_due_at(reference_time)
  end

  def manual_check_due_at(reference_time = Time.current)
    due_at_or_before(reference_time) || reference_time
  end

  def checked?
    last_check_status.present?
  end

  def criteria_summary
    parts = [
      I18n.t("beta.chess.criteria.rating_type", type: rating_type_label),
      I18n.t("beta.chess.criteria.target_rating", rating: target_rating)
    ]
    if baseline_rating.present?
      parts << I18n.t("beta.chess.criteria.baseline_rating", rating: baseline_rating)
    end
    parts.join(" · ")
  end

  private

  def fallback_preview_due_at(reference_time)
    if recurring?
      previous_due_at(reference_time) || next_due_at(reference_time)
    else
      deadline_at
    end
  end

  def deadline_due_at_or_before(reference_time)
    return nil if deadline_at > reference_time
    return nil if last_check_due_at.present? && last_check_due_at >= deadline_at

    deadline_at
  end

  def recurring_due_at_or_before(reference_time)
    return nil if achieved?
    return nil if reference_time > deadline_at

    if interval_recurring?
      interval_due_at_or_before(reference_time)
    else
      daily_due_at_or_before(reference_time)
    end
  end

  def daily_due_at_or_before(reference_time)
    zone = time_zone_object
    local_now = reference_time.in_time_zone(zone)
    hour, minute = check_time_parts
    due_at = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
    return nil if due_at > reference_time
    return nil if due_at > deadline_at
    return nil if last_check_due_at.present? && last_check_due_at >= due_at

    due_at
  end

  def interval_due_at_or_before(reference_time)
    interval = interval_minutes.to_i
    return nil unless interval.positive?

    start_at = schedule_anchor_at
    interval_seconds = interval * 60
    first_due = start_at + interval_seconds.seconds
    return nil if reference_time < first_due

    last_slot =
      if last_check_due_at.present?
        ((last_check_due_at - start_at) / interval_seconds).floor
      else
        0
      end
    due_at = start_at + ((last_slot + 1) * interval_seconds).seconds
    return nil if due_at > reference_time
    return nil if due_at > deadline_at

    due_at
  end

  def daily_next_due_at(reference_time)
    zone = time_zone_object
    local_now = reference_time.in_time_zone(zone)
    hour, minute = check_time_parts
    candidate = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
    candidate += 1.day if candidate <= local_now
    candidate
  end

  def daily_previous_due_at(reference_time)
    zone = time_zone_object
    local_now = reference_time.in_time_zone(zone)
    hour, minute = check_time_parts
    candidate = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
    candidate -= 1.day if candidate > local_now
    candidate
  end

  def interval_next_due_at(reference_time)
    interval = interval_minutes.to_i
    return reference_time unless interval.positive?

    start_at = schedule_anchor_at
    interval_seconds = interval * 60
    elapsed_seconds = reference_time - start_at
    slots = (elapsed_seconds / interval_seconds).floor + 1
    start_at + (slots * interval_seconds).seconds
  end

  def interval_previous_due_at(reference_time)
    interval = interval_minutes.to_i
    return nil unless interval.positive?

    start_at = schedule_anchor_at
    interval_seconds = interval * 60
    first_due = start_at + interval_seconds.seconds
    return nil if reference_time < first_due

    elapsed_seconds = reference_time - start_at
    slots = (elapsed_seconds / interval_seconds).floor
    start_at + (slots * interval_seconds).seconds
  end

  def schedule_anchor_at
    created_at.in_time_zone(time_zone_object).change(sec: 0)
  end

  def time_zone_known
    return if time_zone.blank? || ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, I18n.t("beta.chess.errors.invalid_time_zone"))
  end

  def deadline_in_future
    return if deadline_at.blank?
    return if deadline_at > Time.current

    errors.add(:deadline_at, I18n.t("beta.chess.errors.deadline_must_be_future"))
  end
end
