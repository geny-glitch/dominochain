# frozen_string_literal: true

class AddRecurrenceKindToChessComGoals < ActiveRecord::Migration[7.2]
  def change
    add_column :chess_com_goals, :recurrence_kind, :string, null: false, default: "daily"
    add_column :chess_com_goals, :interval_minutes, :integer
  end
end
