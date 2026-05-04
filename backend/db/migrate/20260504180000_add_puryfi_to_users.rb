# frozen_string_literal: true

class AddPuryfiToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :puryfi_plugin_token, :string
    add_index :users, :puryfi_plugin_token, unique: true
    add_column :users, :puryfi_seconds_per_label, :jsonb, null: false, default: {}
    add_column :users, :puryfi_min_score, :float, null: false, default: 0.5
  end
end
