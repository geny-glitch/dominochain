# frozen_string_literal: true

class WallpaperComplianceCheck < ApplicationRecord
  STATUSES = %w[
    verified
    mismatch
    inconclusive
    skipped
    pending_screenshot
    permissions_missing
    app_unreachable
    chaster_error
  ].freeze
  CHECK_KINDS = %w[scheduled wallpaper_change manual permissions app_unreachable].freeze

  belongs_to :user
  belongs_to :device
  belongs_to :device_screenshot, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :check_kind, inclusion: { in: CHECK_KINDS }
  validates :checked_at, presence: true

  scope :recent, -> { order(checked_at: :desc, id: :desc) }
  scope :with_status, ->(status) { where(status: status) if status.present? }
end
