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

  it "computes due times in the configured time zone" do
    goal = build(:strava_goal, window_days: 3, check_time_minutes: 6 * 60 + 30, time_zone: "Europe/Paris")
    reference = Time.zone.parse("2026-05-05 05:00:00 UTC")

    expect(goal.previous_due_at(reference)).to eq(Time.zone.parse("2026-05-05 04:30:00 UTC"))
    expect(goal.next_due_at(reference)).to eq(Time.zone.parse("2026-05-06 04:30:00 UTC"))
    expect(goal.period_start_for(goal.previous_due_at(reference))).to eq(Time.zone.parse("2026-05-02 04:30:00 UTC"))
  end

  it "exposes sport_type select helpers" do
    goal = build(:strava_goal, activity_types: %w[TrailRun Ride VirtualFoo])

    expect(StravaGoal::STRAVA_SPORT_TYPES).to include("TrailRun", "Yoga")
    expect(StravaGoal.strava_sport_type_options_for_select.map(&:last)).to match_array(StravaGoal::STRAVA_SPORT_TYPES)
    expect(goal.primary_strava_sport_type).to eq("TrailRun")
    expect(goal.supplemental_activity_types_for_form).to eq(%w[Ride VirtualFoo])
  end

  it "returns all activity types as supplemental when none match SportType enum" do
    goal = build(:strava_goal, activity_types: %w[LegacyAlias])

    expect(goal.primary_strava_sport_type).to be_nil
    expect(goal.supplemental_activity_types_for_form).to eq(%w[LegacyAlias])
  end
end
