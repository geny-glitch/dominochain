# frozen_string_literal: true

class AddMismatchSanctionModesToWallpaperEnforcementConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :wallpaper_enforcement_configs, :mismatch_sanction_mode, :string, null: false, default: "strict"
    add_column :wallpaper_enforcement_configs, :mismatch_consecutive_threshold, :integer, null: false, default: 3
    add_column :wallpaper_enforcement_configs, :mismatch_recheck_count, :integer, null: false, default: 0
    add_column :wallpaper_enforcement_configs, :mismatch_consecutive_count, :integer, null: false, default: 0
  end
end
