class Device < ApplicationRecord
  has_many :wallpapers, dependent: :destroy
  has_many :wallpaper_applications, dependent: :destroy

  def current_wallpaper
    wallpaper_applications.recent.first&.wallpaper || wallpapers.order(created_at: :desc).first
  end
end
