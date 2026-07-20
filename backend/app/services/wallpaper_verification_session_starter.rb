# frozen_string_literal: true

class WallpaperVerificationSessionStarter
  class Error < StandardError; end

  def initialize(user)
    @user = user
  end

  def start!(duration_hours:, reference_time: Time.current)
    raise Error, "active_session" if @user.wallpaper_verification_sessions.active.exists?

    device = @user.primary_device
    raise Error, "no_device" unless device

    wallpaper = device.current_wallpaper
    raise Error, "no_wallpaper" unless wallpaper&.image&.attached?

    duration_seconds = WallpaperVerificationSession.seconds_for_hours(duration_hours)
    raise Error, "invalid_duration" unless duration_seconds

    config = @user.ensure_wallpaper_enforcement_config!
    session = nil

    ActiveRecord::Base.transaction do
      config.update!(enabled: true) unless config.enabled?
      session = @user.wallpaper_verification_sessions.create!(
        device: device,
        wallpaper: wallpaper,
        status: WallpaperVerificationSession::ACTIVE_STATUS,
        started_at: reference_time,
        ends_at: reference_time + duration_seconds.seconds,
        config_snapshot: WallpaperVerificationSession.build_config_snapshot(config)
      )
    end

    trigger_initial_check!(device, config, reference_time)
    session
  end

  private

  def trigger_initial_check!(device, config, reference_time)
    WallpaperEnforcementEvaluator.new(@user).evaluate_scheduled_check!(
      device: device,
      reference_time: reference_time
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[WallpaperVerificationSession] user=#{@user.id} initial_check_failed: #{e.class}: #{e.message}"
    )
  end
end
