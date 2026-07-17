# frozen_string_literal: true

class CreateStravaConfigs < ActiveRecord::Migration[7.2]
  def up
    create_table :strava_configs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :scenarios, null: false, default: { "scenarios" => [] }
      t.timestamps
    end

    say_with_time "migrate strava goal scenarios → strava_configs" do
      StravaGoal.reset_column_information
      User.where(id: StravaGoal.select(:user_id).distinct).find_each do |user|
        config = StravaConfig.create!(user: user, scenarios: { "scenarios" => [] })
        migrated_scenarios = []

        user.strava_goals.order(:id).each do |goal|
          set = ScenarioSet.from_hash(goal[:scenarios], source: :strava)
          if set.empty?
            set = ScenarioSet.from_legacy_strava_goal(goal)
          end

          set.scenarios.each do |scenario|
            trigger = scenario.trigger.deep_dup
            if scenario.event == "goal_failed"
              trigger[:goal_id] ||= goal.id
            elsif scenario.event == "any_goal_failed"
              # keep as-is
            else
              next
            end

            migrated_scenarios << {
              "id" => scenario.id,
              "event" => scenario.event == "goal_failed" ? "goal_failed" : scenario.event,
              "trigger" => trigger.deep_stringify_keys,
              "actions" => scenario.actions.map do |action|
                {
                  "possibility_id" => (action[:possibility_id] || action["possibility_id"]).to_s,
                  "config" => (action[:config] || action["config"] || {}).deep_stringify_keys
                }
              end
            }
          end

          goal.update_columns(
            scenarios: { "scenarios" => [] },
            chaster_penalty_seconds: 0,
            failure_sanction: { "items" => [] }
          )
        end

        config.update_columns(scenarios: { "scenarios" => migrated_scenarios }) if migrated_scenarios.any?
      end
    end
  end

  def down
    drop_table :strava_configs
  end
end
