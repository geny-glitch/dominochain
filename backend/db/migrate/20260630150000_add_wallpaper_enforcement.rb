# frozen_string_literal: true

class AddWallpaperEnforcement < ActiveRecord::Migration[7.2]
  DEFAULT_SANCTION = {
    "action" => "none",
    "chaster_seconds" => 3600,
    "pishock_intensity" => 50,
    "pishock_duration" => 1
  }.freeze

  def change
    add_column :devices, :last_seen_at, :datetime
    add_index :devices, :last_seen_at

    add_column :wallpaper_applications, :applied_by, :string, null: false, default: "boss"
    add_index :wallpaper_applications, :applied_by

    create_table :wallpaper_enforcement_configs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.integer :check_interval_minutes, null: false, default: 60
      t.boolean :dismiss_apps_before_capture, null: false, default: true
      t.integer :mismatch_add_time_delay_minutes, null: false, default: 30
      t.integer :mismatch_freeze_delay_minutes, null: false, default: 60
      t.integer :app_unreachable_threshold_minutes, null: false, default: 120
      t.jsonb :mismatch_add_time_sanction, null: false, default: DEFAULT_SANCTION
      t.jsonb :mismatch_freeze_sanction, null: false, default: DEFAULT_SANCTION
      t.jsonb :permissions_lost_sanction, null: false, default: DEFAULT_SANCTION
      t.jsonb :app_unreachable_sanction, null: false, default: DEFAULT_SANCTION
      t.datetime :mismatch_since
      t.datetime :add_time_sanction_applied_at
      t.boolean :frozen_by_enforcement, null: false, default: false
      t.datetime :last_scheduled_check_at
      t.datetime :last_permissions_ok_at
      t.datetime :permissions_lost_sanction_applied_at
      t.datetime :app_unreachable_sanction_applied_at
      t.timestamps
    end

    create_table :wallpaper_compliance_checks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.references :device_screenshot, foreign_key: true
      t.string :status, null: false
      t.string :check_kind, null: false, default: "scheduled"
      t.float :similarity_score
      t.jsonb :sanctions_applied, null: false, default: []
      t.jsonb :details, null: false, default: {}
      t.datetime :checked_at, null: false
      t.timestamps
    end

    add_index :wallpaper_compliance_checks, [:user_id, :checked_at]
    add_index :wallpaper_compliance_checks, [:device_id, :checked_at]
    add_index :wallpaper_compliance_checks, :status
  end
end
