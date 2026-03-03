# frozen_string_literal: true

class AddAlarmSoundToTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :tasks, :alarm_sound, :string, default: "urgent", null: false
  end
end
