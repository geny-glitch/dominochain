# frozen_string_literal: true

class CreateWallpaperVerificationSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :wallpaper_verification_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.references :wallpaper, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false
      t.datetime :ends_at, null: false
      t.jsonb :config_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :wallpaper_verification_sessions, %i[user_id status]
    add_index :wallpaper_verification_sessions, :ends_at
  end
end
