class Device < ApplicationRecord
  belongs_to :user, optional: true

  has_many :wallpapers, dependent: :destroy
  has_many :wallpaper_applications, dependent: :destroy
  has_many :device_screenshots, dependent: :destroy
  has_many :wallpaper_compliance_checks, dependent: :destroy

  def touch_last_seen!(at: Time.current)
    update_column(:last_seen_at, at)
  end

  def reachable?(threshold_minutes:, reference_time: Time.current)
    return false if last_seen_at.blank?

    last_seen_at >= reference_time - threshold_minutes.minutes
  end

  def current_wallpaper
    wallpaper_applications.recent.first&.wallpaper || wallpapers.order(created_at: :desc).first
  end

  def display_name
    name.presence || device_id
  end

  PERMISSION_LABELS = {
    "accessibilité" => "Service accessibilité (captures d'écran)",
    "optimisation batterie" => "Désactiver l'optimisation batterie",
    "notifications" => "Autoriser les notifications"
  }.freeze

  def permissions_missing_list
    return [] if permissions_missing.blank?
    JSON.parse(permissions_missing)
  rescue JSON::ParserError
    []
  end
end
