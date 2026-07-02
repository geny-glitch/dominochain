# frozen_string_literal: true

class WallpaperAlgorithmComparison < ApplicationRecord
  STATUSES = %w[verified mismatch].freeze

  belongs_to :device_screenshot

  validates :algorithm, inclusion: { in: AppSetting::WALLPAPER_VERIFICATION_ALGORITHMS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :algorithm, uniqueness: { scope: :device_screenshot_id }
  validates :compared_at, presence: true

  scope :for_algorithm, ->(algorithm) { where(algorithm: algorithm) }

  def self.upsert_from_result!(device_screenshot:, algorithm:, result:)
    comparison = find_or_initialize_by(device_screenshot: device_screenshot, algorithm: algorithm)
    comparison.assign_attributes(
      status: result.status,
      score: result.score,
      strong_match_count: result.strong_match_count,
      strong_match_ratio: result.strong_match_ratio,
      peak_score: result.peak_score,
      compared_at: Time.current
    )
    comparison.save!
    comparison
  end
end
