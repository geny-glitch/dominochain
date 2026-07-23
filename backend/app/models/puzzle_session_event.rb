# frozen_string_literal: true

class PuzzleSessionEvent < ApplicationRecord
  KINDS = %w[completed completed_in_time failed_time abandoned].freeze

  belongs_to :puzzle_session

  validates :kind, inclusion: { in: KINDS }
  validates :occurred_at, presence: true
  validates :pieces_placed, :pieces_total,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
end
