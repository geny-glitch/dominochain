# frozen_string_literal: true

class ChangeCornertimeCooldownDefault < ActiveRecord::Migration[7.2]
  def up
    change_column_default :cornertime_configs, :violation_cooldown_seconds, from: 30, to: 8
    execute "UPDATE cornertime_configs SET violation_cooldown_seconds = 8 WHERE violation_cooldown_seconds = 30"
  end

  def down
    change_column_default :cornertime_configs, :violation_cooldown_seconds, from: 8, to: 30
  end
end
