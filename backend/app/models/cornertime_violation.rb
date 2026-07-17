# frozen_string_literal: true

class CornertimeViolation < ApplicationRecord
  STATUSES = %w[applied cooldown_skipped source_disabled no_sanctions error].freeze

  belongs_to :cornertime_session

  validates :detected_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :client_violation_id,
    uniqueness: { scope: :cornertime_session_id, allow_nil: true }

  scope :recent, -> { order(detected_at: :desc, id: :desc) }
  scope :applied, -> { where(status: "applied") }
end
