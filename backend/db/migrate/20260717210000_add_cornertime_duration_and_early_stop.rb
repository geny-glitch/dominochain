# frozen_string_literal: true

class AddCornertimeDurationAndEarlyStop < ActiveRecord::Migration[7.2]
  def change
    add_column :cornertime_configs, :early_stop_sanction, :jsonb, null: false, default: { "items" => [] }
    add_column :cornertime_sessions, :planned_duration_seconds, :integer
  end
end
