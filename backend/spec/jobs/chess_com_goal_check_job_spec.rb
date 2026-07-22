# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChessComGoalCheckJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(
      :user,
      :beta,
      chess_com_username: "tester",
      chess_com_player_id: "99",
      chess_com_verified_at: Time.current
    )
  end
  let(:evaluator) { instance_double(ChessComGoalEvaluator) }

  around do |example|
    travel_to Time.zone.parse("2026-07-02 10:00:00 UTC") do
      example.run
    end
  end

  before do
    allow(ChessComGoalEvaluator).to receive(:new).and_return(evaluator)
    allow(evaluator).to receive(:evaluate_due_goal!)
  end

  def create_past_deadline_goal(owner: user, **attrs)
    goal = create(:chess_com_goal, user: owner, deadline_at: 30.days.from_now, **attrs.except(:deadline_at, :enabled))
    updates = {}
    updates[:deadline_at] = attrs[:deadline_at] if attrs.key?(:deadline_at)
    updates[:enabled] = attrs[:enabled] unless attrs[:enabled].nil?
    goal.update_columns(updates) if updates.any?
    goal
  end

  it "evaluates enabled goals past their deadline" do
    due_goal = create_past_deadline_goal(deadline_at: 1.day.ago, enabled: true)
    create(:chess_com_goal, user: user, deadline_at: 5.days.from_now, enabled: true)

    described_class.perform_now

    expect(ChessComGoalEvaluator).to have_received(:new).with(due_goal.user).twice
    expect(evaluator).to have_received(:evaluate_due_goal!).twice
  end

  it "skips disabled goals" do
    create_past_deadline_goal(deadline_at: 1.day.ago, enabled: false)

    described_class.perform_now

    expect(ChessComGoalEvaluator).not_to have_received(:new)
  end

  it "skips users without a verified Chess.com account" do
    create_past_deadline_goal(owner: create(:user, :beta), deadline_at: 1.day.ago, enabled: true)

    described_class.perform_now

    expect(ChessComGoalEvaluator).not_to have_received(:new)
  end

  it "evaluates a specific goal when goal_id is provided" do
    goal = create_past_deadline_goal(deadline_at: 1.day.ago)

    described_class.perform_now(goal.id, "2026-07-02 09:00:00 UTC")

    expect(evaluator).to have_received(:evaluate_due_goal!).with(goal, now: kind_of(ActiveSupport::TimeWithZone))
  end
end
