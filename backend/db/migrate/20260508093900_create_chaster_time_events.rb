# frozen_string_literal: true

class CreateChasterTimeEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :chaster_time_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :chaster_lock_id, null: false
      t.string :source, null: false, default: "api"
      t.integer :seconds, null: false
      t.string :summary
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :chaster_time_events, [:user_id, :occurred_at, :id]
    add_index :chaster_time_events, [:user_id, :chaster_lock_id]
  end
end
