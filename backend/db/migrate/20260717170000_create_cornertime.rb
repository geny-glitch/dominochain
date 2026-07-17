# frozen_string_literal: true

class CreateCornertime < ActiveRecord::Migration[7.2]
  DEFAULT_SANCTION = { "items" => [] }.freeze

  def change
    create_table :cornertime_configs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :movement_sanction, null: false, default: DEFAULT_SANCTION
      t.string :sensitivity, null: false, default: "medium"
      t.integer :violation_cooldown_seconds, null: false, default: 30
      t.integer :calibration_seconds, null: false, default: 5
      t.timestamps
    end

    create_table :cornertime_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :device, foreign_key: true
      t.string :status, null: false, default: "calibrating"
      t.string :client, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :violation_count, null: false, default: 0
      t.timestamps
    end

    add_index :cornertime_sessions, [:user_id, :started_at]
    add_index :cornertime_sessions, [:user_id, :status]

    create_table :cornertime_violations do |t|
      t.references :cornertime_session, null: false, foreign_key: true
      t.datetime :detected_at, null: false
      t.float :motion_score
      t.string :client_violation_id
      t.jsonb :actions_executed, null: false, default: []
      t.string :status, null: false, default: "applied"
      t.timestamps
    end

    add_index :cornertime_violations, [:cornertime_session_id, :detected_at]
    add_index :cornertime_violations, [:cornertime_session_id, :client_violation_id],
              unique: true,
              where: "client_violation_id IS NOT NULL",
              name: "index_cornertime_violations_on_session_and_client_id"
  end
end
