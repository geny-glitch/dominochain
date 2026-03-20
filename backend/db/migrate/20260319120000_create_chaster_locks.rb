# frozen_string_literal: true

class CreateChasterLocks < ActiveRecord::Migration[7.2]
  def change
    create_table :chaster_locks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :chaster_lock_id, null: false
      t.string :title
      t.string :status, default: "locked", null: false
      t.datetime :start_date
      t.datetime :end_date
      t.boolean :is_frozen, default: false, null: false
      t.datetime :frozen_at
      t.integer :total_duration
      t.datetime :unlocked_at
      t.jsonb :raw_data
      t.timestamps
    end

    add_index :chaster_locks, [:user_id, :chaster_lock_id], unique: true
    add_index :chaster_locks, [:user_id, :status]
    add_index :chaster_locks, [:user_id, :end_date]
  end
end
