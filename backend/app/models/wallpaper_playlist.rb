# frozen_string_literal: true

class WallpaperPlaylist < ApplicationRecord
  belongs_to :device
  has_many :items,
    -> { order(:position) },
    class_name: "WallpaperPlaylistItem",
    dependent: :destroy,
    inverse_of: :wallpaper_playlist

  validates :interval_seconds, numericality: {
    only_integer: true,
    greater_than_or_equal_to: WallpaperRotations::Schedule::MIN_INTERVAL_SECONDS,
    less_than_or_equal_to: WallpaperRotations::Schedule::MAX_INTERVAL_SECONDS
  }
  validates :anchor_at, presence: true

  def ordered_wallpapers
    items.filter_map(&:wallpaper).select { |wallpaper| wallpaper.image.attached? }
  end

  def active?
    enabled? && ordered_wallpapers.size >= 2
  end

  def change_every_label
    if interval_seconds >= 60 && (interval_seconds % 60).zero?
      I18n.t("wallpaper.rotation_every_minutes", count: interval_seconds / 60)
    else
      I18n.t("wallpaper.rotation_every_seconds", count: interval_seconds)
    end
  end
end
