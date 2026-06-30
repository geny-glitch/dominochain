# frozen_string_literal: true

class WallpaperCheckResultNotifier
  def self.notify!(check)
    new(check).notify!
  end

  def initialize(check)
    @check = check
    @device = check.device
    @user = check.user
  end

  def notify!
    return if @device.fcm_token.blank?

    FcmService.send_wallpaper_check_result_notification(
      device: @device,
      check: @check,
      title: title,
      body: body
    )
  end

  private

  def title
    I18n.with_locale(user_locale) do
      I18n.t("fcm.wallpaper_check.title")
    end
  end

  def body
    I18n.with_locale(user_locale) do
      case @check.status
      when "verified" then verified_body
      when "mismatch" then mismatch_body
      when "inconclusive" then I18n.t("fcm.wallpaper_check.body.inconclusive")
      when "permissions_missing" then I18n.t("fcm.wallpaper_check.body.permissions_missing")
      when "app_unreachable" then I18n.t("fcm.wallpaper_check.body.app_unreachable")
      when "chaster_error" then I18n.t("fcm.wallpaper_check.body.chaster_error")
      else I18n.t("fcm.wallpaper_check.body.other")
      end
    end
  end

  def verified_body
    I18n.t("fcm.wallpaper_check.body.verified")
  end

  def mismatch_body
    sanctions = Array(@check.sanctions_applied)

    if (seconds = chaster_seconds_added(sanctions)).positive?
      return I18n.t("fcm.wallpaper_check.body.mismatch_punished", duration: format_duration(seconds))
    end

    if sanctions.any? { |s| s["kind"] == "mismatch_freeze" && s["action"] == "chaster_freeze" }
      return I18n.t("fcm.wallpaper_check.body.mismatch_frozen")
    end

    if sanctions.any? { |s| s["action"] == "pishock" }
      return I18n.t("fcm.wallpaper_check.body.mismatch_pishock")
    end

    if pending_add_time_warning?
      return I18n.t(
        "fcm.wallpaper_check.body.mismatch_warning",
        duration: format_duration(pending_chaster_seconds),
        remaining: format_duration(remaining_grace_seconds)
      )
    end

    I18n.t("fcm.wallpaper_check.body.mismatch")
  end

  def pending_add_time_warning?
    config = enforcement_config
    return false unless config

    sanction = config.mismatch_add_time_sanction_object
    return false unless sanction.active? && sanction.action == "chaster_add_time"
    return false if config.add_time_sanction_applied_at.present?
    return false if config.mismatch_since.blank?

    remaining_grace_seconds.positive?
  end

  def remaining_grace_seconds
    config = enforcement_config
    return 0 unless config&.mismatch_since

    delay = config.mismatch_add_time_delay_minutes.minutes
    elapsed = @check.checked_at - config.mismatch_since
    [delay - elapsed, 0].max.to_i
  end

  def pending_chaster_seconds
    enforcement_config&.mismatch_add_time_sanction_object&.chaster_seconds.to_i
  end

  def enforcement_config
    @user.wallpaper_enforcement_config
  end

  def chaster_seconds_added(sanctions)
    sanctions.sum do |sanction|
      next 0 unless sanction["kind"] == "mismatch_add_time" && sanction["action"] == "chaster_add_time"

      sanction["chaster_seconds"].to_i
    end
  end

  def format_duration(total_seconds)
    s = total_seconds.to_i
    return I18n.t("fcm.wallpaper_check.duration.zero") if s <= 0

    days, rem = s.divmod(86_400)
    hours, rem = rem.divmod(3600)
    mins, secs = rem.divmod(60)
    parts = []
    parts << I18n.t("fcm.wallpaper_check.duration.days", count: days) if days.positive?
    parts << I18n.t("fcm.wallpaper_check.duration.hours", count: hours) if hours.positive?
    parts << I18n.t("fcm.wallpaper_check.duration.minutes", count: mins) if mins.positive?
    parts << I18n.t("fcm.wallpaper_check.duration.seconds", count: secs) if parts.empty? || secs.positive?
    parts.join(" ")
  end

  def user_locale
    locale = @user.beta_ui_prefs&.dig("locale").presence
    sym = locale.to_s.downcase.split("-").first&.to_sym
    %i[en fr es].include?(sym) ? sym : I18n.default_locale
  end
end
