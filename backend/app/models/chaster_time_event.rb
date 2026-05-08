# frozen_string_literal: true

class ChasterTimeEvent < ApplicationRecord
  SOURCES = %w[
    api
    puryfi
    cigarettes
    showcase_backdoor
    showcase_game
    strava_goal
  ].freeze

  belongs_to :user

  validates :chaster_lock_id, :occurred_at, presence: true
  validates :seconds, numericality: { only_integer: true, other_than: 0 }
  validates :source, inclusion: { in: SOURCES }

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
end
