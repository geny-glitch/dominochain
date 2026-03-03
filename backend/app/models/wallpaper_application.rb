# frozen_string_literal: true

class WallpaperApplication < ApplicationRecord
  belongs_to :device
  belongs_to :wallpaper

  scope :recent, -> { order(applied_at: :desc) }
end
