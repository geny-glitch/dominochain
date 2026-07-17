# frozen_string_literal: true

class AddScenariosToCornertimeConfigs < ActiveRecord::Migration[7.2]
  def up
    add_column :cornertime_configs, :scenarios, :jsonb, null: false, default: { "scenarios" => [] }

    say_with_time "migrate cornertime sanctions → scenarios" do
      CornertimeConfig.reset_column_information
      CornertimeConfig.find_each do |config|
        next if config.scenarios.is_a?(Hash) && Array(config.scenarios["scenarios"]).any?

        migrated = ScenarioSet.from_legacy_cornertime(config)
        config.update_columns(scenarios: migrated.to_h)
      end
    end
  end

  def down
    remove_column :cornertime_configs, :scenarios
  end
end
