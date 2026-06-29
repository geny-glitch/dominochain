# frozen_string_literal: true

class DeviceScreenshot < ApplicationRecord
  include ImagePreviewVariant

  belongs_to :device
  belongs_to :wallpaper, optional: true

  has_one_attached :image do |attachable|
    ImagePreviewVariant::AttachmentConfig.call(attachable)
  end

  VERIFICATION_STATUSES = %w[pending verified mismatch inconclusive skipped].freeze

  validates :captured_at, presence: true
  validates :verification_status, inclusion: { in: VERIFICATION_STATUSES }
end
