# frozen_string_literal: true

class CreateCigaretteEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :cigarette_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :count, null: false, default: 1
      t.date :smoked_on, null: false
      t.datetime :smoked_at, null: false
      t.integer :chaster_seconds, null: false, default: 0
      t.string :chaster_lock_id
      t.boolean :chaster_applied, null: false, default: false
      t.string :chaster_error

      t.timestamps
    end

    add_index :cigarette_entries, [:user_id, :smoked_on]
    add_index :cigarette_entries, [:user_id, :smoked_at]
  end
end
