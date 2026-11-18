# frozen_string_literal: true

class CreateZapPrograms < ActiveRecord::Migration[7.2]
  def change
    create_table :zap_programs do |t|
      t.references :beta, null: false, foreign_key: { to_table: :users }
      t.string :source, null: false
      t.references :boss, null: true, foreign_key: { to_table: :users }
      t.boolean :armed, null: false, default: false
      t.integer :generation, null: false, default: 0
      t.datetime :busy_until
      t.timestamps
    end

    add_index :zap_programs, [ :beta_id, :source ], unique: true

    create_table :zap_slots do |t|
      t.references :zap_program, null: false, foreign_key: true
      t.string :schedule_kind, null: false
      t.integer :time_of_day_minutes
      t.datetime :fires_at
      t.integer :interval_minutes
      t.integer :window_start_minutes
      t.integer :window_end_minutes
      t.string :pattern_kind, null: false
      t.integer :intensity
      t.integer :intensity_min
      t.integer :intensity_max
      t.integer :duration, null: false
      t.integer :count
      t.integer :gap_seconds
      t.date :last_fired_on
      t.datetime :last_fired_at
      t.datetime :fired_at
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :zap_slots, [ :zap_program_id, :position ]
  end
end
