# frozen_string_literal: true

class WallpaperEnforcementConfig < ApplicationRecord
  MIN_INTERVAL_MINUTES = 1
  MAX_INTERVAL_MINUTES = 24 * 60
  MIN_DELAY_MINUTES = 0
  MAX_DELAY_MINUTES = 7 * 24 * 60
  MIN_UNREACHABLE_MINUTES = 30
  MAX_UNREACHABLE_MINUTES = 7 * 24 * 60
  MIN_CONSECUTIVE_THRESHOLD = 2
  MAX_CONSECUTIVE_THRESHOLD = 10
  MAX_DOUBLE_CHECK_RECHECKS = 3

  SANCTION_MODE_STRICT = "strict"
  SANCTION_MODE_DOUBLE_CHECK = "double_check"
  SANCTION_MODE_CONSECUTIVE_FAILURES = "consecutive_failures"
  SANCTION_MODES = [
    SANCTION_MODE_STRICT,
    SANCTION_MODE_DOUBLE_CHECK,
    SANCTION_MODE_CONSECUTIVE_FAILURES
  ].freeze

  belongs_to :user

  validates :check_interval_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: MIN_INTERVAL_MINUTES, less_than_or_equal_to: MAX_INTERVAL_MINUTES }
  validate :scenarios_are_valid

  scope :due_for_check, lambda { |reference_time = Time.current|
    where(enabled: true).where(
      "last_scheduled_check_at IS NULL OR last_scheduled_check_at + (check_interval_minutes * interval '1 minute') <= ?",
      reference_time
    )
  }

  def reload(*)
    @scenario_set = nil
    @stored_scenario_set = nil
    super
  end

  def scenario_set
    @scenario_set ||= begin
      stored = stored_scenario_set
      stored.any? ? stored : ScenarioSet.from_legacy_config(self)
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

  # Compat readers used by evaluator / device reachability.
  # When scenarios JSONB is populated it wins; otherwise legacy columns/JSONB are used
  # so specs and transitional records can still mutate delay/mode columns directly.
  def mismatch_sanction_object
    if stored_scenario_set.any?
      mismatch_scenario&.to_sanction_set || SanctionSet.from_hash({}, allowed: wallpaper_allowed)
    else
      SanctionSet.from_hash(mismatch_sanction, allowed: wallpaper_allowed)
    end
  end

  def permissions_lost_sanction_object
    if stored_scenario_set.any?
      permissions_lost_scenario&.to_sanction_set || SanctionSet.from_hash({}, allowed: wallpaper_allowed)
    else
      SanctionSet.from_hash(permissions_lost_sanction, allowed: wallpaper_allowed)
    end
  end

  def app_unreachable_sanction_object
    if stored_scenario_set.any?
      app_unreachable_scenario&.to_sanction_set || SanctionSet.from_hash({}, allowed: wallpaper_allowed)
    else
      SanctionSet.from_hash(app_unreachable_sanction, allowed: wallpaper_allowed)
    end
  end

  def mismatch_delay_minutes
    if (scenario = stored_scenario_set.for_event("mismatch"))
      scenario.delay_minutes
    else
      self[:mismatch_delay_minutes] || 30
    end
  end

  def mismatch_sanction_mode
    if (scenario = stored_scenario_set.for_event("mismatch"))
      scenario.mode
    else
      self[:mismatch_sanction_mode] || SANCTION_MODE_STRICT
    end
  end

  def mismatch_consecutive_threshold
    if (scenario = stored_scenario_set.for_event("mismatch"))
      scenario.consecutive_threshold
    else
      self[:mismatch_consecutive_threshold] || MIN_CONSECUTIVE_THRESHOLD
    end
  end

  def permissions_lost_delay_minutes
    if (scenario = stored_scenario_set.for_event("permissions_lost"))
      scenario.delay_minutes
    else
      self[:permissions_lost_delay_minutes] || 0
    end
  end

  def app_unreachable_delay_minutes
    if (scenario = stored_scenario_set.for_event("app_unreachable"))
      scenario.delay_minutes
    else
      self[:app_unreachable_delay_minutes] || 0
    end
  end

  def app_unreachable_threshold_minutes
    if (scenario = stored_scenario_set.for_event("app_unreachable"))
      scenario.threshold_minutes
    else
      self[:app_unreachable_threshold_minutes] || 120
    end
  end

  def due_for_scheduled_check?(reference_time = Time.current)
    return false unless enabled?

    return true if last_scheduled_check_at.blank?

    last_scheduled_check_at + check_interval_minutes.minutes <= reference_time
  end

  def reset_mismatch_state!
    update!(
      mismatch_since: nil,
      add_time_sanction_applied_at: nil,
      mismatch_recheck_count: 0,
      mismatch_consecutive_count: 0
    )
  end

  def strict_sanction_mode?
    mismatch_sanction_mode == SANCTION_MODE_STRICT
  end

  def double_check_sanction_mode?
    mismatch_sanction_mode == SANCTION_MODE_DOUBLE_CHECK
  end

  def consecutive_failures_sanction_mode?
    mismatch_sanction_mode == SANCTION_MODE_CONSECUTIVE_FAILURES
  end

  def reset_permissions_lost_state!
    update!(
      permissions_lost_since: nil,
      permissions_lost_sanction_applied_at: nil
    )
  end

  def reset_app_unreachable_state!
    update!(
      app_unreachable_since: nil,
      app_unreachable_sanction_applied_at: nil
    )
  end

  def assign_scenarios!(scenario_set)
    self.scenarios = scenario_set.to_h
    # Clear legacy sanction JSONB so empty scenarios are not resurrected by fallback.
    blank = { "items" => [] }
    self.mismatch_sanction = blank
    self.permissions_lost_sanction = blank
    self.app_unreachable_sanction = blank
    @scenario_set = scenario_set
    @stored_scenario_set = scenario_set
  end

  private

  def wallpaper_allowed
    BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
  end

  def stored_scenario_set
    @stored_scenario_set ||= ScenarioSet.from_hash(self[:scenarios], source: :wallpaper)
  end

  def scenarios_are_valid
    stored_scenario_set.scenarios.each do |scenario|
      sanction = scenario.to_sanction_set(allowed: wallpaper_allowed)
      if sanction.enabled?("chaster.add_time") && !sanction.item_for("chaster.add_time")&.active?
        errors.add(:scenarios, :invalid)
      end
      if sanction.enabled?("leverage_photo.lock") && !sanction.item_for("leverage_photo.lock")&.active?
        errors.add(:scenarios, :invalid)
      end
    end
  end
end
