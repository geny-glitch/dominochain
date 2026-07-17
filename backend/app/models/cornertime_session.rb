# frozen_string_literal: true

class CornertimeSession < ApplicationRecord
  STATUSES = %w[calibrating active stopped completed].freeze
  CLIENTS = %w[android web].freeze
  OPEN_STATUSES = %w[calibrating active].freeze
  ALLOWED_DURATIONS_MINUTES = [1, 5, 10, 15, 20, 30, 45, 60].freeze
  # Clock skew / timer jitter: still count as completed if within this window of the end.
  EARLY_STOP_GRACE_SECONDS = 3

  belongs_to :user
  belongs_to :device, optional: true
  has_many :cornertime_violations, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :client, inclusion: { in: CLIENTS }
  validates :started_at, presence: true
  validates :violation_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :planned_duration_seconds,
    numericality: {
      only_integer: true,
      greater_than: 0
    },
    allow_nil: true
  validate :planned_duration_is_allowed, if: -> { planned_duration_seconds.present? }

  scope :recent, -> { order(started_at: :desc, id: :desc) }
  scope :open, -> { where(status: OPEN_STATUSES) }

  def open?
    OPEN_STATUSES.include?(status)
  end

  def active?
    status == "active"
  end

  def mark_active!
    update!(status: "active") if status == "calibrating"
  end

  def planned_duration_minutes
    return nil if planned_duration_seconds.blank?

    planned_duration_seconds / 60
  end

  def ends_at
    return nil if started_at.blank? || planned_duration_seconds.blank?

    started_at + planned_duration_seconds
  end

  def early_if_stopped_now?(at: Time.current)
    return false if planned_duration_seconds.blank? || started_at.blank?

    at < (started_at + planned_duration_seconds - EARLY_STOP_GRACE_SECONDS)
  end

  # Prefer CornertimeSessionFinisher — kept for callers that only need a hard stop.
  def stop!
    return unless open?

    update!(status: "stopped", ended_at: Time.current)
  end

  def self.seconds_for_minutes(minutes)
    minutes = minutes.to_i
    return nil unless ALLOWED_DURATIONS_MINUTES.include?(minutes)

    minutes * 60
  end

  private

  def planned_duration_is_allowed
    minutes = planned_duration_seconds.to_i / 60
    return if ALLOWED_DURATIONS_MINUTES.include?(minutes) && (planned_duration_seconds % 60).zero?

    errors.add(:planned_duration_seconds, :inclusion)
  end
end
