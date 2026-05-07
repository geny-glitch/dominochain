# frozen_string_literal: true

class StravaGoalCheck < ApplicationRecord
  STATUSES = %w[passed failed chaster_error].freeze

  belongs_to :strava_goal
  belongs_to :user

  validates :period_start_at, :period_end_at, :due_at, :checked_at, presence: true
  validates :required_count, numericality: { only_integer: true, greater_than: 0 }
  validates :valid_count, :total_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :chaster_penalty_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :due_at, uniqueness: { scope: :strava_goal_id }

  scope :recent, -> { order(due_at: :desc, checked_at: :desc) }
end
