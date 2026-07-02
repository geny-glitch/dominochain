# frozen_string_literal: true

class AppSetting < ApplicationRecord
  WALLPAPER_VERIFICATION_ALGORITHMS = {
    "grid_fuzzy" => "Grid fuzzy (SSIM + dHash median)",
    "local_match" => "Local match (strict patch detection)"
  }.freeze
  DEFAULT_WALLPAPER_VERIFICATION_ALGORITHM = "local_match"

  validates :wallpaper_verification_algorithm,
            inclusion: { in: WALLPAPER_VERIFICATION_ALGORITHMS.keys }

  def self.instance
    first || create!(influencer_names: "")
  end

  def self.wallpaper_verification_algorithm
    instance.wallpaper_verification_algorithm.presence || DEFAULT_WALLPAPER_VERIFICATION_ALGORITHM
  end

  def influencer_names_list
    return [] if influencer_names.blank?
    influencer_names.strip.split(/\r?\n/).map(&:strip).reject(&:blank?)
  end

  def influencer_names_list=(names)
    self.influencer_names = names.is_a?(Array) ? names.join("\n") : names.to_s
  end
end
