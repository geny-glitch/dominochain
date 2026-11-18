# frozen_string_literal: true

class CreateWallpaperPlaylists < ActiveRecord::Migration[7.2]
  def change
    create_table :wallpaper_playlists do |t|
      t.references :device, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.integer :interval_seconds, null: false, default: 30
      t.boolean :collages_enabled, null: false, default: true
      t.datetime :anchor_at, null: false
      t.timestamps
    end

    create_table :wallpaper_playlist_items do |t|
      t.references :wallpaper_playlist, null: false, foreign_key: true
      t.references :wallpaper, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:wallpaper_playlist_id, :position], name: "index_wallpaper_playlist_items_on_playlist_and_position"
    end
  end
end
