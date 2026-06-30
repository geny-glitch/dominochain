# frozen_string_literal: true

class WallpaperApplication < ApplicationRecord
  APPLIED_BY_VALUES = %w[boss beta_self].freeze

  belongs_to :device
  belongs_to :wallpaper

  validates :applied_by, inclusion: { in: APPLIED_BY_VALUES }

  scope :recent, -> { order(applied_at: :desc) }
  scope :by_boss, -> { where(applied_by: "boss") }
  scope :by_beta_self, -> { where(applied_by: "beta_self") }
end
