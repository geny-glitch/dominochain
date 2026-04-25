# frozen_string_literal: true

class AddShowcaseBackdoorAndTimeAdditions < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :showcase_backdoor_enabled, :boolean, default: true, null: false

    create_table :showcase_time_additions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :seconds, null: false
      t.string :player_name, null: false
      t.text :message, null: false
      t.boolean :chaster_applied, default: false, null: false
      t.string :chaster_error
      t.timestamps
    end

    add_index :showcase_time_additions, [:user_id, :created_at]
  end
end
