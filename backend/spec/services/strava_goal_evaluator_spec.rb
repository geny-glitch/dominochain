# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaGoalEvaluator do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :beta) }
  let(:strava_service) { instance_double(StravaService) }
  let(:chaster_service) { instance_double(ChasterService) }
  let(:evaluator) { described_class.new(user, strava_service: strava_service, chaster_service: chaster_service) }
  let(:due_at) { Time.zone.parse("2026-05-05 22:00:00") }

  describe "#evaluate_goal!" do
    it "passes when enough Strava activities match all configured criteria" do
      goal = create(
        :strava_goal,
        user: user,
        required_activity_count: 2,
        window_days: 3,
        min_duration_seconds: 30.minutes.to_i,
        min_calories: 300,
        activity_types: [ "Run" ],
        device_names: [ "Garmin" ],
        chaster_penalty_seconds: 2.hours.to_i
      )
      allow(strava_service).to receive(:activities_between).and_return([
        { id: 1, type: "Run", sport_type: "Run", duration_seconds: 40.minutes.to_i, calories: 450, device_name: "Garmin Fenix" },
        { id: 2, type: "Run", sport_type: "Run", duration_seconds: 31.minutes.to_i, calories: 310, device_name: "Garmin Forerunner" },
        { id: 3, type: "Ride", sport_type: "Ride", duration_seconds: 2.hours.to_i, calories: 600, device_name: "Wahoo" }
      ])

      check = evaluator.evaluate_goal!(goal, due_at: due_at)

      expect(strava_service).to have_received(:activities_between).with(
        start_time: due_at - 3.days,
        end_time: due_at,
        include_details: true
      )
      expect(check.status).to eq("passed")
      expect(check.valid_count).to eq(2)
      expect(check.total_count).to eq(3)
      expect(check.chaster_applied).to be false
      expect(check.window_days).to eq(3)
      expect(goal.reload.last_check_status).to eq("passed")
    end

    it "adds the configured Chaster penalty once when the goal fails" do
      goal = create(:strava_goal, user: user, required_activity_count: 2, window_days: 1, min_duration_seconds: 30.minutes.to_i, chaster_penalty_seconds: 90.minutes.to_i)
      allow(strava_service).to receive(:activities_between).and_return([
        { id: 1, type: "Run", sport_type: "Run", duration_seconds: 20.minutes.to_i, calories: nil, device_name: "" }
      ])
      allow(chaster_service).to receive(:current_lock).and_return({ id: "lock-strava" })
      allow(chaster_service).to receive(:add_time_to_lock)

      first = evaluator.evaluate_goal!(goal, due_at: due_at)
      second = evaluator.evaluate_goal!(goal, due_at: due_at)

      expect(first.status).to eq("failed")
      expect(first.chaster_applied).to be true
      expect(first.chaster_lock_id).to eq("lock-strava")
      expect(chaster_service).to have_received(:add_time_to_lock).once.with(
        "lock-strava",
        90.minutes.to_i,
        source: "strava_goal",
        summary: "Objectif Strava manqué: Cardio rolling",
        metadata: { goal_id: goal.id, due_at: a_string_starting_with(due_at.iso8601.first(19)) }
      )
      expect(second.id).to eq(first.id)
      expect(goal.strava_goal_checks.count).to eq(1)
    end

    it "records a Chaster error when no active lock exists" do
      goal = create(:strava_goal, user: user, required_activity_count: 1, min_duration_seconds: 30.minutes.to_i)
      allow(strava_service).to receive(:activities_between).and_return([])
      allow(chaster_service).to receive(:current_lock).and_return(nil)

      check = evaluator.evaluate_goal!(goal, due_at: due_at)

      expect(check.status).to eq("chaster_error")
      expect(check.chaster_applied).to be false
      expect(check.chaster_error).to eq("Aucun cadenas Chaster actif.")
    end

    it "evaluates due goals at their configured local check time" do
      travel_to Time.zone.parse("2026-05-06 00:30:00") do
        due_goal = create(:strava_goal, user: user, window_days: 1, check_time_minutes: 22 * 60, time_zone: "UTC")
        create(:strava_goal, user: user, window_days: 1, check_time_minutes: 23 * 60, time_zone: "UTC")
        allow(strava_service).to receive(:activities_between).and_return([
          { id: 1, type: "Run", sport_type: "Run", duration_seconds: 40.minutes.to_i, calories: nil, device_name: "" }
        ])
        allow(chaster_service).to receive(:current_lock).and_return(nil)

        checks = evaluator.evaluate_due_goals!

        expect(checks.map(&:strava_goal_id)).to eq([ due_goal.id ])
        expect(checks.first.due_at).to eq(Time.zone.parse("2026-05-06 00:00:00"))
      end
    end
  end
end
