# frozen_string_literal: true

class AddStravaConnector < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :strava_access_token, :string
    add_column :users, :strava_refresh_token, :string
    add_column :users, :strava_token_expires_at, :datetime
    add_column :users, :strava_athlete_id, :string

    create_table :strava_goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :required_activity_count, null: false, default: 1
      t.integer :window_days, null: false, default: 7
      t.integer :check_time_minutes, null: false, default: 0
      t.string :time_zone, null: false, default: "Europe/Paris"
      t.integer :min_duration_seconds
      t.integer :min_calories
      t.jsonb :activity_types, null: false, default: []
      t.jsonb :device_names, null: false, default: []
      t.integer :chaster_penalty_seconds, null: false
      t.datetime :last_check_due_at
      t.datetime :last_check_period_start_at
      t.datetime :last_check_period_end_at
      t.integer :last_check_valid_count
      t.integer :last_check_total_count
      t.string :last_check_status
      t.boolean :last_check_chaster_applied, null: false, default: false
      t.string :last_check_chaster_error
      t.jsonb :last_check_details, null: false, default: {}
      t.timestamps
    end

    add_index :strava_goals, [:user_id, :enabled]

    create_table :strava_goal_checks do |t|
      t.references :strava_goal, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :due_at, null: false
      t.datetime :period_start_at, null: false
      t.datetime :period_end_at, null: false
      t.integer :window_days, null: false
      t.integer :check_time_minutes, null: false
      t.string :time_zone, null: false
      t.integer :required_count, null: false
      t.integer :valid_count, null: false, default: 0
      t.integer :total_count, null: false, default: 0
      t.string :status, null: false
      t.integer :chaster_penalty_seconds, null: false
      t.string :chaster_lock_id
      t.boolean :chaster_applied, null: false, default: false
      t.string :chaster_error
      t.jsonb :details, null: false, default: {}
      t.datetime :checked_at, null: false
      t.timestamps
    end

    add_index :strava_goal_checks, [:strava_goal_id, :due_at], unique: true
    add_index :strava_goal_checks, [:user_id, :due_at]
  end
end
