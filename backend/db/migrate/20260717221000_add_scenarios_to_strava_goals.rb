# frozen_string_literal: true

class AddScenariosToStravaGoals < ActiveRecord::Migration[7.2]
  def up
    add_column :strava_goals, :scenarios, :jsonb, null: false, default: { "scenarios" => [] }

    say_with_time "migrate strava failure sanctions → scenarios" do
      StravaGoal.reset_column_information
      StravaGoal.find_each do |goal|
        next if goal.scenarios.is_a?(Hash) && Array(goal.scenarios["scenarios"]).any?

        migrated = ScenarioSet.from_legacy_strava_goal(goal)
        goal.update_columns(scenarios: migrated.to_h)
      end
    end
  end

  def down
    remove_column :strava_goals, :scenarios
  end
end
