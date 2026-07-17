# frozen_string_literal: true

class AddScenariosToWallpaperEnforcementConfigs < ActiveRecord::Migration[7.2]
  def up
    add_column :wallpaper_enforcement_configs, :scenarios, :jsonb, null: false, default: { "scenarios" => [] }

    say_with_time "migrate wallpaper sanctions → scenarios" do
      WallpaperEnforcementConfig.reset_column_information
      WallpaperEnforcementConfig.find_each do |config|
        next if config.scenarios.is_a?(Hash) && Array(config.scenarios["scenarios"]).any?

        migrated = ScenarioSet.from_legacy_config(config)
        config.update_columns(scenarios: migrated.to_h)
      end
    end
  end

  def down
    remove_column :wallpaper_enforcement_configs, :scenarios
  end
end
