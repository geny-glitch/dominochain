# frozen_string_literal: true

# Read-only view of wallpaper enforcement settings, optionally frozen by an active verification session.
class WallpaperEnforcementSnapshot
  def self.for(user)
    session = user.wallpaper_verification_sessions.active.first
    new(config: user.wallpaper_enforcement_config, session: session)
  end

  def initialize(config:, session: nil)
    @config = config
    @session = session&.active? ? session : nil
    @frozen = @session&.config_snapshot.is_a?(Hash) ? @session.config_snapshot : {}
  end

  def active_session?
    @session.present?
  end

  def enabled?
    @config&.enabled? || active_session?
  end

  def locked_wallpaper
    @session&.wallpaper
  end

  def due_for_scheduled_check?(reference_time = Time.current)
    return false unless enabled?
    return false unless @config

    return true if @config.last_scheduled_check_at.blank?

    @config.last_scheduled_check_at + check_interval_minutes.minutes <= reference_time
  end

  def check_interval_minutes
    frozen_integer("check_interval_minutes") || @config&.check_interval_minutes || WallpaperEnforcementConfig::MIN_INTERVAL_MINUTES
  end

  def dismiss_apps_before_capture
    key = "dismiss_apps_before_capture"
    return @frozen[key] if @frozen.key?(key)

    @config&.dismiss_apps_before_capture != false
  end

  def mismatch_delay_minutes
    frozen_integer("mismatch_delay_minutes") || @config&.mismatch_delay_minutes || 30
  end

  def mismatch_sanction_mode
    frozen_string("mismatch_sanction_mode") || @config&.mismatch_sanction_mode || WallpaperEnforcementConfig::SANCTION_MODE_STRICT
  end

  def mismatch_consecutive_threshold
    frozen_integer("mismatch_consecutive_threshold") || @config&.mismatch_consecutive_threshold || WallpaperEnforcementConfig::MIN_CONSECUTIVE_THRESHOLD
  end

  def permissions_lost_delay_minutes
    frozen_integer("permissions_lost_delay_minutes") || @config&.permissions_lost_delay_minutes || 0
  end

  def app_unreachable_delay_minutes
    frozen_integer("app_unreachable_delay_minutes") || @config&.app_unreachable_delay_minutes || 0
  end

  def app_unreachable_threshold_minutes
    frozen_integer("app_unreachable_threshold_minutes") || @config&.app_unreachable_threshold_minutes || 120
  end

  def scenario_set
    if @frozen["scenarios"].present?
      ScenarioSet.from_hash(@frozen["scenarios"], source: :wallpaper)
    else
      @config&.scenario_set || ScenarioSet.new(source: :wallpaper)
    end
  end

  def scenario_for(event)
    scenario_set.for_event(event)
  end

  def mismatch_scenario
    scenario_for("mismatch")
  end

  def permissions_lost_scenario
    scenario_for("permissions_lost")
  end

  def app_unreachable_scenario
    scenario_for("app_unreachable")
  end

  def mismatch_sanction_object
    mismatch_scenario&.to_sanction_set(allowed: wallpaper_allowed) || SanctionSet.from_hash({}, allowed: wallpaper_allowed)
  end

  def permissions_lost_sanction_object
    permissions_lost_scenario&.to_sanction_set(allowed: wallpaper_allowed) || SanctionSet.from_hash({}, allowed: wallpaper_allowed)
  end

  def app_unreachable_sanction_object
    app_unreachable_scenario&.to_sanction_set(allowed: wallpaper_allowed) || SanctionSet.from_hash({}, allowed: wallpaper_allowed)
  end

  def strict_sanction_mode?
    mismatch_sanction_mode == WallpaperEnforcementConfig::SANCTION_MODE_STRICT
  end

  def double_check_sanction_mode?
    mismatch_sanction_mode == WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK
  end

  def consecutive_failures_sanction_mode?
    mismatch_sanction_mode == WallpaperEnforcementConfig::SANCTION_MODE_CONSECUTIVE_FAILURES
  end

  private

  def wallpaper_allowed
    BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
  end

  def frozen_integer(key)
    return nil unless @frozen.key?(key)

    @frozen[key].to_i
  end

  def frozen_string(key)
    return nil unless @frozen.key?(key)

    @frozen[key].to_s.presence
  end
end
