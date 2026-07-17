# frozen_string_literal: true

class StravaConfig < ApplicationRecord
  belongs_to :user

  validate :scenarios_are_valid

  def reload(*)
    @scenario_set = nil
    @stored_scenario_set = nil
    super
  end

  def scenario_set
    @scenario_set ||= stored_scenario_set
  end

  def scenario_for(event)
    scenario_set.for_event(event)
  end

  def scenarios_for_goal_failure(goal)
    scenario_set.scenarios_for_goal_failure(goal)
  end

  def assign_scenarios!(incoming)
    self.scenarios = incoming.to_h
    @scenario_set = incoming
    @stored_scenario_set = incoming
  end

  def remove_scenarios_for_goal!(goal_id)
    remaining = scenario_set.scenarios.reject do |scenario|
      scenario.event == "goal_failed" &&
        (scenario.trigger[:goal_id] || scenario.trigger["goal_id"]).to_i == goal_id.to_i
    end
    assign_scenarios!(ScenarioSet.new(scenarios: remaining))
    save!
  end

  private

  def stored_scenario_set
    @stored_scenario_set ||= ScenarioSet.from_hash(self[:scenarios], source: :strava)
  end

  def strava_allowed
    BetaEvents::ScenarioRegistry.allowed_actions_for(:strava)
  end

  def scenarios_are_valid
    scenario_set.scenarios.each do |scenario|
      if scenario.event == "goal_failed"
        goal_id = (scenario.trigger[:goal_id] || scenario.trigger["goal_id"]).to_i
        if goal_id <= 0 || !user.strava_goals.exists?(id: goal_id)
          errors.add(:scenarios, :invalid)
          next
        end
      end

      sanction = scenario.to_sanction_set(allowed: strava_allowed)
      if sanction.enabled?("chaster.add_time") && !sanction.item_for("chaster.add_time")&.active?
        errors.add(:scenarios, :invalid)
      end
      if sanction.enabled?("leverage_photo.lock") && !sanction.item_for("leverage_photo.lock")&.active?
        errors.add(:scenarios, :invalid)
      end
    end
  end
end
