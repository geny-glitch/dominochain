# frozen_string_literal: true

class CreateDeviceWallpaperSamples < ActiveRecord::Migration[7.2]
  def change
    create_table :device_wallpaper_samples do |t|
      t.references :device, null: false, foreign_key: true
      t.references :wallpaper, foreign_key: true, null: true
      t.datetime :sampled_at, null: false
      t.float :similarity_score
      t.string :verification_status, default: "pending", null: false
      t.datetime :verified_at

      t.timestamps
    end

    add_index :device_wallpaper_samples, [:device_id, :sampled_at]
    add_index :device_wallpaper_samples, :verification_status
  end
end
