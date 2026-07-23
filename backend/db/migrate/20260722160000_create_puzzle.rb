# frozen_string_literal: true

class CreatePuzzle < ActiveRecord::Migration[7.2]
  def change
    create_table :puzzle_configs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :default_piece_count, null: false, default: 25
      t.string :default_reference_mode, null: false, default: "blurred"
      t.integer :default_time_limit_seconds
      t.integer :cooldown_seconds, null: false, default: 0
      t.jsonb :scenarios, null: false, default: { "scenarios" => [] }
      t.timestamps
    end

    create_table :puzzle_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :leverage_photo, foreign_key: true
      t.references :wallpaper, foreign_key: true
      t.string :status, null: false, default: "assigned"
      t.string :origin, null: false, default: "self"
      t.string :image_source, null: false
      t.integer :piece_count, null: false
      t.integer :grid_cols, null: false
      t.integer :grid_rows, null: false
      t.string :reference_mode, null: false, default: "blurred"
      t.integer :time_limit_seconds
      t.datetime :deadline_at
      t.datetime :started_at
      t.datetime :ended_at
      t.bigint :layout_seed, null: false
      t.integer :pieces_placed, null: false, default: 0
      t.integer :pieces_total, null: false
      t.jsonb :config_snapshot, null: false, default: {}
      t.timestamps
    end

    add_index :puzzle_sessions, [:user_id, :status]
    add_index :puzzle_sessions, [:user_id, :created_at]

    create_table :puzzle_session_events do |t|
      t.references :puzzle_session, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :pieces_placed, null: false, default: 0
      t.integer :pieces_total, null: false
      t.jsonb :actions_executed, null: false, default: []
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :puzzle_session_events, [:puzzle_session_id, :occurred_at]
  end
end
