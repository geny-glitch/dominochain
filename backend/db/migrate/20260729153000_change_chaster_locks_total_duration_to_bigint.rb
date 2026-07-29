# frozen_string_literal: true

class ChangeChasterLocksTotalDurationToBigint < ActiveRecord::Migration[7.2]
  def up
    change_column :chaster_locks, :total_duration, :bigint
  end

  def down
    change_column :chaster_locks, :total_duration, :integer
  end
end
