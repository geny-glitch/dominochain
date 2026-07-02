# frozen_string_literal: true

class WallpaperPairReview < ApplicationRecord
  EXPECTED_STATUSES = %w[verified mismatch ignored].freeze

  belongs_to :device_screenshot
  belongs_to :wallpaper
  belongs_to :reviewed_by, class_name: "User"

  validates :expected_status, inclusion: { in: EXPECTED_STATUSES }
  validates :reviewed_at, presence: true
  validates :device_screenshot_id, uniqueness: true

  scope :verified, -> { where(expected_status: "verified") }
  scope :mismatch, -> { where(expected_status: "mismatch") }
  scope :ignored, -> { where(expected_status: "ignored") }
  scope :for_regression, -> { where.not(expected_status: "ignored") }

  scope :disagreeing_with_local_match, lambda {
    for_regression
      .joins(:device_screenshot)
      .joins(<<~SQL.squish)
        INNER JOIN wallpaper_algorithm_comparisons
          ON wallpaper_algorithm_comparisons.device_screenshot_id = wallpaper_pair_reviews.device_screenshot_id
         AND wallpaper_algorithm_comparisons.algorithm = 'local_match'
      SQL
      .where("wallpaper_pair_reviews.expected_status != wallpaper_algorithm_comparisons.status")
  }
end
