# frozen_string_literal: true

class DeviceScreenshot < ApplicationRecord
  include ImagePreviewVariant

  belongs_to :device
  belongs_to :wallpaper, optional: true
  has_one :wallpaper_pair_review, dependent: :destroy

  has_one_attached :image do |attachable|
    ImagePreviewVariant::AttachmentConfig.call(attachable)
  end

  VERIFICATION_STATUSES = %w[pending verified mismatch inconclusive skipped].freeze
  INCONCLUSIVE_REASONS = %w[
    capture_before_wallpaper_change
    variants_not_ready
    compare_timeout
    compare_error
    ambiguous_match
  ].freeze

  validates :captured_at, presence: true
  validates :verification_status, inclusion: { in: VERIFICATION_STATUSES }
  validates :inconclusive_reason, inclusion: { in: INCONCLUSIVE_REASONS }, allow_nil: true

  scope :labelable, lambda {
    where.not(wallpaper_id: nil)
      .joins(:image_attachment)
      .joins(wallpaper: :image_attachment)
  }

  scope :unreviewed, lambda {
    left_outer_joins(:wallpaper_pair_review).where(wallpaper_pair_reviews: { id: nil })
  }
end
