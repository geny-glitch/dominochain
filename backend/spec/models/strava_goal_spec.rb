# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaGoal do
  it "requires at least one criterion" do
    goal = build(
      :strava_goal,
      min_duration_seconds: nil,
      min_calories: nil,
      activity_types: [],
      device_names: []
    )

    expect(goal).not_to be_valid
    expect(goal.errors.full_messages).to include("Ajoute au moins un critère Strava.")
  end

  it "normalizes comma separated lists" do
    goal = build(:strava_goal, activity_types: "Run, Ride\nRun", device_names: "Garmin; Wahoo")

    expect(goal.activity_types).to eq(%w[Run Ride])
    expect(goal.device_names).to eq(%w[Garmin Wahoo])
  end
end
