class Device < ApplicationRecord
  belongs_to :user, optional: true

  has_many :wallpapers, dependent: :destroy
  has_many :wallpaper_applications, dependent: :destroy
  has_many :device_screenshots, dependent: :destroy

  def current_wallpaper
    wallpaper_applications.recent.first&.wallpaper || wallpapers.order(created_at: :desc).first
  end

  def display_name
    name.presence || device_id
  end
end
