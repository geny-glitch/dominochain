# frozen_string_literal: true

class CornertimeSession < ApplicationRecord
  STATUSES = %w[calibrating active stopped completed].freeze
  CLIENTS = %w[android web].freeze
  OPEN_STATUSES = %w[calibrating active].freeze

  belongs_to :user
  belongs_to :device, optional: true
  has_many :cornertime_violations, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :client, inclusion: { in: CLIENTS }
  validates :started_at, presence: true
  validates :violation_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

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

  def stop!
    return unless open?

    update!(status: "stopped", ended_at: Time.current)
  end
end
