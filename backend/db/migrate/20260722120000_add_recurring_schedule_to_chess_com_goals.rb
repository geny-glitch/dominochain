# frozen_string_literal: true

class AddRecurringScheduleToChessComGoals < ActiveRecord::Migration[7.2]
  def change
    add_column :chess_com_goals, :schedule_mode, :string, null: false, default: "deadline"
    add_column :chess_com_goals, :check_time_minutes, :integer
  end
end
