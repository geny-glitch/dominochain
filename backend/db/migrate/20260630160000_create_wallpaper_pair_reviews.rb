# frozen_string_literal: true

class CreateWallpaperPairReviews < ActiveRecord::Migration[7.2]
  def change
    create_table :wallpaper_pair_reviews do |t|
      t.references :device_screenshot, null: false, foreign_key: true, index: { unique: true }
      t.references :wallpaper, null: false, foreign_key: true
      t.string :expected_status, null: false
      t.references :reviewed_by, null: false, foreign_key: { to_table: :users }
      t.datetime :reviewed_at, null: false

      t.timestamps
    end

    add_index :wallpaper_pair_reviews, :expected_status
  end
end
