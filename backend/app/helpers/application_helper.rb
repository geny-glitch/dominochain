module ApplicationHelper
  include WallpaperPathHelper

  def discord_invite_url
    Rails.application.config.x.discord_invite_url.to_s.strip
  end

  def discord_link_available?
    discord_invite_url.present?
  end

  def format_chaster_remaining(seconds)
    return t("time.finished") if seconds.nil? || seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3600
    mins = (seconds % 3600) / 60
    secs = seconds % 60

    if days.positive?
      t("time.remaining_days_hours_mins_secs", days:, hours:, mins:, secs:)
    elsif hours.positive?
      t("time.remaining_hours_mins_secs", hours:, mins:, secs:)
    elsif mins.positive?
      t("time.remaining_mins_secs", mins:, secs:)
    else
      t("time.remaining_secs", secs:)
    end
  end

  def format_leverage_duration(seconds)
    s = seconds.to_i
    return t("leverage_photo.duration.zero") if s <= 0

    days, rem = s.divmod(86_400)
    hours, rem = rem.divmod(3600)
    mins = rem / 60
    parts = []
    parts << t("leverage_photo.duration.days", count: days) if days.positive?
    parts << t("leverage_photo.duration.hours", count: hours) if hours.positive?
    parts << t("leverage_photo.duration.minutes", count: mins) if mins.positive?
    parts << t("leverage_photo.duration.zero") if parts.empty?
    parts.join(" ")
  end
end
