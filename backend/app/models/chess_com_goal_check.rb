# frozen_string_literal: true

class ChessComGoalCheck < ApplicationRecord
  STATUSES = %w[passed failed chaster_error].freeze

  belongs_to :chess_com_goal
  belongs_to :user

  validates :due_at, :checked_at, presence: true
  validates :rating_type, inclusion: { in: ChessComGoal::RATING_TYPES }
  validates :target_rating, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :due_at, uniqueness: { scope: :chess_com_goal_id }

  scope :recent, -> { order(due_at: :desc, checked_at: :desc) }
end
