# frozen_string_literal: true

class WallpaperPlaylistItem < ApplicationRecord
  belongs_to :wallpaper_playlist, inverse_of: :items
  belongs_to :wallpaper

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
