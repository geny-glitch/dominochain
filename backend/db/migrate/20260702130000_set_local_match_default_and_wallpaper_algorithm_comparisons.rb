# frozen_string_literal: true

class SetLocalMatchDefaultAndWallpaperAlgorithmComparisons < ActiveRecord::Migration[7.2]
  def up
    change_column_default :app_settings, :wallpaper_verification_algorithm, from: "grid_fuzzy", to: "local_match"
    execute <<~SQL.squish
      UPDATE app_settings SET wallpaper_verification_algorithm = 'local_match'
      WHERE wallpaper_verification_algorithm = 'grid_fuzzy'
    SQL

    create_table :wallpaper_algorithm_comparisons do |t|
      t.references :device_screenshot, null: false, foreign_key: true
      t.string :algorithm, null: false
      t.string :status, null: false
      t.float :score
      t.integer :strong_match_count
      t.float :strong_match_ratio
      t.float :peak_score
      t.datetime :compared_at, null: false

      t.timestamps
    end

    add_index :wallpaper_algorithm_comparisons,
              %i[device_screenshot_id algorithm],
              unique: true,
              name: "index_wallpaper_algo_comparisons_on_screenshot_and_algorithm"
  end

  def down
    drop_table :wallpaper_algorithm_comparisons

    execute <<~SQL.squish
      UPDATE app_settings SET wallpaper_verification_algorithm = 'grid_fuzzy'
      WHERE wallpaper_verification_algorithm = 'local_match'
    SQL
    change_column_default :app_settings, :wallpaper_verification_algorithm, from: "local_match", to: "grid_fuzzy"
  end
end
