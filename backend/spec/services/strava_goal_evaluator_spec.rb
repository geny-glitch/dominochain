# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaGoalEvaluator do
  let(:user) { create(:user, :beta) }
  let(:strava_service) { instance_double(StravaService) }
  let(:chaster_service) { instance_double(ChasterService) }
  let(:evaluator) { described_class.new(user, strava_service: strava_service, chaster_service: chaster_service) }
  let(:week_start_on) { Date.new(2026, 4, 27) }

  describe "#evaluate_goal!" do
    it "passes when enough Strava activities match all configured criteria" do
      goal = create(
        :strava_goal,
        user: user,
        weekly_required_count: 2,
        min_duration_seconds: 30.minutes.to_i,
        min_calories: 300,
        activity_types: ["Run"],
        device_names: ["Garmin"],
        chaster_penalty_seconds: 2.hours.to_i
      )
      allow(strava_service).to receive(:activities_between).and_return([
        { id: 1, type: "Run", sport_type: "Run", duration_seconds: 40.minutes.to_i, calories: 450, device_name: "Garmin Fenix" },
        { id: 2, type: "Run", sport_type: "Run", duration_seconds: 31.minutes.to_i, calories: 310, device_name: "Garmin Forerunner" },
        { id: 3, type: "Ride", sport_type: "Ride", duration_seconds: 2.hours.to_i, calories: 600, device_name: "Wahoo" }
      ])

      check = evaluator.evaluate_goal!(goal, week_start_on: week_start_on)

      expect(strava_service).to have_received(:activities_between).with(
        start_time: week_start_on.beginning_of_day,
        end_time: (week_start_on + 1.week).beginning_of_day,
        include_details: true
      )
      expect(check.status).to eq("passed")
      expect(check.valid_count).to eq(2)
      expect(check.total_count).to eq(3)
      expect(check.chaster_applied).to be false
      expect(goal.reload.last_check_status).to eq("passed")
    end

    it "adds the configured Chaster penalty once when the goal fails" do
      goal = create(:strava_goal, user: user, weekly_required_count: 2, min_duration_seconds: 30.minutes.to_i, chaster_penalty_seconds: 90.minutes.to_i)
      allow(strava_service).to receive(:activities_between).and_return([
        { id: 1, type: "Run", sport_type: "Run", duration_seconds: 20.minutes.to_i, calories: nil, device_name: "" }
      ])
      allow(chaster_service).to receive(:current_lock).and_return({ id: "lock-strava" })
      allow(chaster_service).to receive(:add_time_to_lock)

      first = evaluator.evaluate_goal!(goal, week_start_on: week_start_on)
      second = evaluator.evaluate_goal!(goal, week_start_on: week_start_on)

      expect(first.status).to eq("failed")
      expect(first.chaster_applied).to be true
      expect(first.chaster_lock_id).to eq("lock-strava")
      expect(chaster_service).to have_received(:add_time_to_lock).once.with("lock-strava", 90.minutes.to_i)
      expect(second.id).to eq(first.id)
      expect(goal.strava_goal_checks.count).to eq(1)
    end

    it "records a Chaster error when no active lock exists" do
      goal = create(:strava_goal, user: user, weekly_required_count: 1, min_duration_seconds: 30.minutes.to_i)
      allow(strava_service).to receive(:activities_between).and_return([])
      allow(chaster_service).to receive(:current_lock).and_return(nil)

      check = evaluator.evaluate_goal!(goal, week_start_on: week_start_on)

      expect(check.status).to eq("chaster_error")
      expect(check.chaster_applied).to be false
      expect(check.chaster_error).to eq("Aucun cadenas Chaster actif.")
    end
  end
end
