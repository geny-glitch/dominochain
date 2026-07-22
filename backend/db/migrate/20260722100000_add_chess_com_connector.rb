# frozen_string_literal: true

class AddChessComConnector < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :chess_com_username, :string
    add_column :users, :chess_com_player_id, :string
    add_column :users, :chess_com_verified_at, :datetime
    add_column :users, :chess_com_verification_code, :string
    add_column :users, :chess_com_verification_code_expires_at, :datetime

    add_index :users, :chess_com_player_id, unique: true, where: "chess_com_player_id IS NOT NULL"

    create_table :chess_com_goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.string :rating_type, null: false, default: "blitz"
      t.integer :target_rating, null: false
      t.integer :baseline_rating
      t.datetime :deadline_at, null: false
      t.string :time_zone, null: false, default: "Europe/Paris"
      t.datetime :last_check_due_at
      t.integer :last_check_rating
      t.integer :last_check_target_rating
      t.string :last_check_status
      t.boolean :last_check_chaster_applied, null: false, default: false
      t.string :last_check_chaster_error
      t.jsonb :last_check_details, null: false, default: {}
      t.timestamps
    end

    add_index :chess_com_goals, [ :user_id, :enabled ]

    create_table :chess_com_goal_checks do |t|
      t.references :chess_com_goal, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :due_at, null: false
      t.string :rating_type, null: false
      t.integer :target_rating, null: false
      t.integer :baseline_rating
      t.integer :rating_at_check
      t.string :status, null: false
      t.string :chaster_lock_id
      t.boolean :chaster_applied, null: false, default: false
      t.string :chaster_error
      t.jsonb :details, null: false, default: {}
      t.datetime :checked_at, null: false
      t.timestamps
    end

    add_index :chess_com_goal_checks, [ :chess_com_goal_id, :due_at ], unique: true
    add_index :chess_com_goal_checks, [ :user_id, :due_at ]

    create_table :chess_com_configs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :scenarios, null: false, default: { "scenarios" => [] }
      t.timestamps
    end
  end
end
