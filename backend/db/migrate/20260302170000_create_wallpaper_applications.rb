# frozen_string_literal: true

class CreateWallpaperApplications < ActiveRecord::Migration[7.2]
  def change
    create_table :wallpaper_applications do |t|
      t.references :device, null: false, foreign_key: true
      t.references :wallpaper, null: false, foreign_key: true
      t.datetime :applied_at, null: false

      t.timestamps
    end

    add_index :wallpaper_applications, [:device_id, :applied_at]

    reversible do |dir|
      dir.up do
        Device.find_each do |device|
          device.wallpapers.order(created_at: :desc).each do |wallpaper|
            WallpaperApplication.create!(
              device_id: device.id,
              wallpaper_id: wallpaper.id,
              applied_at: wallpaper.created_at
            )
          end
        end
      end
    end
  end
end
