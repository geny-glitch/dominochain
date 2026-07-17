# frozen_string_literal: true

# Generic scenarios value object: event + shared trigger settings + actions.
# Stored as JSONB, e.g. on wallpaper_enforcement_configs / cornertime_configs / strava_goals:
#   { "scenarios" => [ { "id" => "...", "event" => "mismatch", "trigger" => {...}, "actions" => [...] } ] }
class ScenarioSet
  Scenario = Struct.new(:id, :event, :trigger, :actions, keyword_init: true) do
    def any_actions?
      actions.any?
    end

    def delay_minutes
      trigger[:delay_minutes] || trigger["delay_minutes"] || 0
    end

    def mode
      (trigger[:mode] || trigger["mode"] || WallpaperEnforcementConfig::SANCTION_MODE_STRICT).to_s
    end

    def consecutive_threshold
      trigger[:consecutive_threshold] || trigger["consecutive_threshold"] ||
        WallpaperEnforcementConfig::MIN_CONSECUTIVE_THRESHOLD
    end

    def threshold_minutes
      trigger[:threshold_minutes] || trigger["threshold_minutes"]
    end

    def to_sanction_set(allowed: nil)
      source = BetaEvents::ScenarioRegistry.source_for_event(event)
      allowed ||= if source
        BetaEvents::ScenarioRegistry.allowed_actions_for(source)
      else
        BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
      end
      items_hash = {
        "items" => actions.map do |action|
          {
            "possibility_id" => action[:possibility_id] || action["possibility_id"],
            "enabled" => true,
            "config" => action[:config] || action["config"] || {}
          }
        end
      }
      SanctionSet.from_hash(items_hash, allowed: allowed)
    end

    def to_h
      {
        "id" => id,
        "event" => event,
        "trigger" => trigger.deep_stringify_keys,
        "actions" => actions.map do |action|
          pid = (action[:possibility_id] || action["possibility_id"]).to_s
          cfg = (action[:config] || action["config"] || {}).deep_stringify_keys
          { "possibility_id" => pid, "config" => cfg }
        end
      }
    end
  end

  attr_reader :scenarios

  def self.from_hash(value, source: nil)
    hash = value.is_a?(Hash) ? value.deep_stringify_keys : {}
    raw_list = hash["scenarios"]
    return new(scenarios: []) unless raw_list.is_a?(Array)

    scenarios = raw_list.filter_map { |raw| build_scenario(raw, source: source) }
    new(scenarios: scenarios)
  end

  def self.from_params(raw, source: nil)
    return new(scenarios: []) if raw.blank?

    hash = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    hash = hash.deep_stringify_keys
    list = hash["scenarios"]
    if list.is_a?(Hash)
      list = list.sort_by { |k, _| k.to_i }.map { |_, scenario| coerce_nested_actions(scenario) }
      hash = hash.merge("scenarios" => list)
    elsif list.is_a?(Array)
      hash = hash.merge("scenarios" => list.map { |scenario| coerce_nested_actions(scenario) })
    end
    from_hash(hash, source: source)
  end

  def self.coerce_nested_actions(scenario)
    return scenario unless scenario.is_a?(Hash)

    actions = scenario["actions"]
    return scenario unless actions.is_a?(Hash)

    scenario.merge(
      "actions" => actions.sort_by { |k, _| k.to_i }.map(&:last)
    )
  end
  private_class_method :coerce_nested_actions

  def self.from_legacy_config(config)
    scenarios = []
    allowed = BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)

    mismatch_sanction = SanctionSet.from_hash(
      config[:mismatch_sanction] || config.mismatch_sanction,
      allowed: allowed
    )
    if mismatch_sanction.any_active?
      scenarios << Scenario.new(
        id: SecureRandom.uuid,
        event: "mismatch",
        trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
          "mismatch",
          {
            delay_minutes: config[:mismatch_delay_minutes],
            mode: config[:mismatch_sanction_mode],
            consecutive_threshold: config[:mismatch_consecutive_threshold]
          },
          source: :wallpaper
        ),
        actions: active_actions_from_sanction(mismatch_sanction)
      )
    end

    permissions_sanction = SanctionSet.from_hash(
      config[:permissions_lost_sanction] || config.permissions_lost_sanction,
      allowed: allowed
    )
    if permissions_sanction.any_active?
      scenarios << Scenario.new(
        id: SecureRandom.uuid,
        event: "permissions_lost",
        trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
          "permissions_lost",
          { delay_minutes: config[:permissions_lost_delay_minutes] },
          source: :wallpaper
        ),
        actions: active_actions_from_sanction(permissions_sanction)
      )
    end

    unreachable_sanction = SanctionSet.from_hash(
      config[:app_unreachable_sanction] || config.app_unreachable_sanction,
      allowed: allowed
    )
    if unreachable_sanction.any_active?
      scenarios << Scenario.new(
        id: SecureRandom.uuid,
        event: "app_unreachable",
        trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
          "app_unreachable",
          {
            delay_minutes: config[:app_unreachable_delay_minutes],
            threshold_minutes: config[:app_unreachable_threshold_minutes]
          },
          source: :wallpaper
        ),
        actions: active_actions_from_sanction(unreachable_sanction)
      )
    end

    new(scenarios: scenarios)
  end

  def self.from_legacy_sanction(sanction_hash, event:, source:, allowed: nil)
    allowed ||= BetaEvents::ScenarioRegistry.allowed_actions_for(source)
    sanction = SanctionSet.from_hash(sanction_hash, allowed: allowed)
    return new(scenarios: []) unless sanction.any_active?

    new(
      scenarios: [
        Scenario.new(
          id: SecureRandom.uuid,
          event: event.to_s,
          trigger: BetaEvents::ScenarioRegistry.normalize_trigger(event, {}, source: source),
          actions: active_actions_from_sanction(sanction)
        )
      ]
    )
  end

  def self.from_legacy_cornertime(config)
    movement = from_legacy_sanction(
      config[:movement_sanction] || config.movement_sanction,
      event: "movement_detected",
      source: :cornertime,
      allowed: BetaEvents::SourceRegistry.allowed_for(:cornertime, :movement_detected)
    )
    early = from_legacy_sanction(
      config[:early_stop_sanction] || config.early_stop_sanction,
      event: "early_stop",
      source: :cornertime,
      allowed: BetaEvents::SourceRegistry.allowed_for(:cornertime, :early_stop)
    )
    new(scenarios: movement.scenarios + early.scenarios)
  end

  def self.from_legacy_strava_goal(goal)
    allowed = BetaEvents::ScenarioRegistry.allowed_actions_for(:strava)
    actions = []

    penalty_seconds = goal[:chaster_penalty_seconds] || goal.chaster_penalty_seconds
    if penalty_seconds.to_i.positive?
      actions << {
        possibility_id: "chaster.add_time",
        config: BetaEvents::ActionRegistry.normalize_config(
          "chaster.add_time",
          { "seconds" => penalty_seconds.to_i }
        )
      }
    end

    leverage = SanctionSet.from_hash(
      goal[:failure_sanction] || goal.failure_sanction,
      allowed: BetaEvents::SourceRegistry.allowed_for(:strava_goal, :failed_penalty)
    )
    actions.concat(active_actions_from_sanction(leverage))
    return new(scenarios: []) if actions.empty?

    new(
      scenarios: [
        Scenario.new(
          id: SecureRandom.uuid,
          event: "goal_failed",
          trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
            "goal_failed",
            { goal_id: goal.id },
            source: :strava
          ),
          actions: actions
        )
      ]
    )
  end

  def self.active_actions_from_sanction(sanction)
    sanction.active_items.map do |item|
      { possibility_id: item.possibility_id, config: item.config }
    end
  end

  def self.build_scenario(raw, source: nil)
    return nil unless raw.is_a?(Hash)

    event = raw["event"].to_s
    return nil unless BetaEvents::ScenarioRegistry.find(event, source: source)

    actions = Array(raw["actions"]).filter_map do |action|
      next unless action.is_a?(Hash)

      pid = action["possibility_id"].to_s
      next if pid.blank?
      next unless BetaEvents::ActionRegistry.find(pid)

      {
        possibility_id: pid,
        config: BetaEvents::ActionRegistry.normalize_config(pid, action["config"] || {})
      }
    end

    return nil if actions.empty?

    trigger = BetaEvents::ScenarioRegistry.normalize_trigger(event, raw["trigger"] || {}, source: source)
    if event == "goal_failed" && trigger[:goal_id].to_i <= 0
      return nil
    end

    Scenario.new(
      id: raw["id"].presence || SecureRandom.uuid,
      event: event,
      trigger: trigger,
      actions: actions
    )
  end

  def initialize(scenarios:)
    @scenarios = Array(scenarios)
  end

  def empty?
    scenarios.empty?
  end

  def any?
    scenarios.any?
  end

  def for_event(event)
    scenarios.find { |s| s.event == event.to_s }
  end

  def for_event_and_goal(event, goal_id:)
    scenarios.find do |s|
      s.event == event.to_s &&
        (s.trigger[:goal_id] || s.trigger["goal_id"]).to_i == goal_id.to_i
    end
  end

  def scenarios_for_goal_failure(goal)
    goal_id = goal.is_a?(StravaGoal) ? goal.id : goal.to_i
    matching = scenarios.select do |s|
      case s.event
      when "any_goal_failed" then true
      when "goal_failed"
        (s.trigger[:goal_id] || s.trigger["goal_id"]).to_i == goal_id.to_i
      else
        false
      end
    end
    return matching if matching.any?

    # Legacy: per-goal scenarios still stored on StravaGoal (pre-migration rows).
    if goal.is_a?(StravaGoal)
      legacy = ScenarioSet.from_hash(goal[:scenarios], source: :strava)
      legacy = ScenarioSet.from_legacy_strava_goal(goal) if legacy.empty?
      legacy.scenarios.select { |s| s.event == "goal_failed" }
    else
      []
    end
  end

  def to_h
    { "scenarios" => scenarios.map(&:to_h) }
  end
end
