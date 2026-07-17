# frozen_string_literal: true

# Wallpaper enforcement scenarios: event + shared trigger settings + actions.
# Stored as JSONB on wallpaper_enforcement_configs.scenarios:
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
      allowed ||= BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
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

  def self.from_hash(value)
    hash = value.is_a?(Hash) ? value.deep_stringify_keys : {}
    raw_list = hash["scenarios"]
    return new(scenarios: []) unless raw_list.is_a?(Array)

    scenarios = raw_list.filter_map { |raw| build_scenario(raw) }
    new(scenarios: scenarios)
  end

  def self.from_params(raw)
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
    from_hash(hash)
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

    mismatch_sanction = SanctionSet.from_hash(
      config[:mismatch_sanction] || config.mismatch_sanction,
      allowed: BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
    )
    if mismatch_sanction.any_active?
      scenarios << Scenario.new(
        id: SecureRandom.uuid,
        event: "mismatch",
        trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
          "mismatch",
          delay_minutes: config[:mismatch_delay_minutes],
          mode: config[:mismatch_sanction_mode],
          consecutive_threshold: config[:mismatch_consecutive_threshold]
        ),
        actions: active_actions_from_sanction(mismatch_sanction)
      )
    end

    permissions_sanction = SanctionSet.from_hash(
      config[:permissions_lost_sanction] || config.permissions_lost_sanction,
      allowed: BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
    )
    if permissions_sanction.any_active?
      scenarios << Scenario.new(
        id: SecureRandom.uuid,
        event: "permissions_lost",
        trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
          "permissions_lost",
          delay_minutes: config[:permissions_lost_delay_minutes]
        ),
        actions: active_actions_from_sanction(permissions_sanction)
      )
    end

    unreachable_sanction = SanctionSet.from_hash(
      config[:app_unreachable_sanction] || config.app_unreachable_sanction,
      allowed: BetaEvents::SourceRegistry.allowed_for(:wallpaper, :default)
    )
    if unreachable_sanction.any_active?
      scenarios << Scenario.new(
        id: SecureRandom.uuid,
        event: "app_unreachable",
        trigger: BetaEvents::ScenarioRegistry.normalize_trigger(
          "app_unreachable",
          delay_minutes: config[:app_unreachable_delay_minutes],
          threshold_minutes: config[:app_unreachable_threshold_minutes]
        ),
        actions: active_actions_from_sanction(unreachable_sanction)
      )
    end

    new(scenarios: scenarios)
  end

  def self.active_actions_from_sanction(sanction)
    sanction.active_items.map do |item|
      { possibility_id: item.possibility_id, config: item.config }
    end
  end

  def self.build_scenario(raw)
    return nil unless raw.is_a?(Hash)

    event = raw["event"].to_s
    return nil unless BetaEvents::ScenarioRegistry.find(event)

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

    Scenario.new(
      id: raw["id"].presence || SecureRandom.uuid,
      event: event,
      trigger: BetaEvents::ScenarioRegistry.normalize_trigger(event, raw["trigger"] || {}),
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

  def to_h
    { "scenarios" => scenarios.map(&:to_h) }
  end
end
