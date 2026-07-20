# frozen_string_literal: true

class AddPuryfiPishockSettingsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :puryfi_shock_level_per_label, :jsonb, null: false, default: {}
    add_column :users, :puryfi_pishock_level_settings, :jsonb, null: false, default: {
      "1" => { "intensity" => 10, "duration" => 1 },
      "2" => { "intensity" => 30, "duration" => 1 },
      "3" => { "intensity" => 60, "duration" => 1 }
    }
  end
end
