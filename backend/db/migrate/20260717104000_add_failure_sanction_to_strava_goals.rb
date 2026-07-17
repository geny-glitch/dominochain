# frozen_string_literal: true

class AddFailureSanctionToStravaGoals < ActiveRecord::Migration[7.2]
  def change
    add_column :strava_goals, :failure_sanction, :jsonb, null: false, default: {}
  end
end
