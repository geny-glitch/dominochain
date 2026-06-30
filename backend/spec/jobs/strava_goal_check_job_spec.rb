# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaGoalCheckJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :beta) }
  let(:evaluator) { instance_double(StravaGoalEvaluator) }

  around do |example|
    travel_to Time.zone.parse("2026-05-05 05:00:00 UTC") do
      example.run
    end
  end

  before do
    allow(StravaGoalEvaluator).to receive(:new).and_return(evaluator)
    allow(evaluator).to receive(:evaluate_goal!)
  end

  it "evaluates enabled goals that are due for check" do
    due_goal = create(:strava_goal, user: user, check_time_minutes: 0, enabled: true)
    create(:strava_goal, user: user, check_time_minutes: 12 * 60, enabled: true)

    described_class.perform_now

    expect(StravaGoalEvaluator).to have_received(:new).with(due_goal.user).once
    expect(evaluator).to have_received(:evaluate_goal!).with(due_goal, due_at: kind_of(ActiveSupport::TimeWithZone))
  end

  it "skips disabled goals" do
    create(:strava_goal, user: user, enabled: false)

    described_class.perform_now

    expect(StravaGoalEvaluator).not_to have_received(:new)
  end

  it "evaluates a specific goal when goal_id is provided" do
    goal = create(:strava_goal, user: user)

    described_class.perform_now(goal.id, "2026-05-05 04:30:00 UTC")

    expect(evaluator).to have_received(:evaluate_goal!).with(goal, due_at: kind_of(ActiveSupport::TimeWithZone))
  end
end
