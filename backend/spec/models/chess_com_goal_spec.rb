# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChessComGoal, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  it "requires a future deadline on create" do
    goal = build(:chess_com_goal, deadline_at: 1.hour.ago)
    expect(goal).not_to be_valid
    expect(goal.errors[:deadline_at]).to be_present
  end

  it "rejects unknown rating types" do
    goal = build(:chess_com_goal, rating_type: "correspondence")
    expect(goal).not_to be_valid
    expect(goal.errors[:rating_type]).to be_present
  end

  it "returns due_at only once before a check exists in deadline mode" do
    goal = create(:chess_com_goal, deadline_at: 30.days.from_now)
    goal.update_columns(deadline_at: 1.day.ago)
    expect(goal.due_at_or_before(Time.current)).to eq(goal.deadline_at)

    goal.update_columns(last_check_due_at: goal.deadline_at, last_check_status: "passed")
    expect(goal.due_at_or_before(Time.current)).to be_nil
  end

  it "requires check_time_minutes for daily recurring goals" do
    goal = build(:chess_com_goal, :recurring, check_time_minutes: nil)
    expect(goal).not_to be_valid
    expect(goal.errors[:check_time_minutes]).to be_present
  end

  it "requires interval_minutes for interval recurring goals" do
    goal = build(:chess_com_goal, :interval_recurring, interval_minutes: nil)
    expect(goal).not_to be_valid
    expect(goal.errors[:interval_minutes]).to be_present
  end

  it "returns a daily due_at until the end date in recurring mode" do
    travel_to Time.zone.parse("2026-07-02 21:00:00") do
      goal = create(
        :chess_com_goal,
        :recurring,
        check_time_minutes: 20 * 60,
        deadline_at: Time.zone.parse("2026-07-10 20:00:00")
      )

      due_at = goal.due_at_or_before(Time.current)
      expect(due_at).to eq(Time.zone.parse("2026-07-02 20:00:00"))

      goal.update_columns(last_check_due_at: due_at, last_check_status: "failed")
      expect(goal.due_at_or_before(Time.current)).to be_nil
    end
  end

  it "stops recurring checks after the goal is passed" do
    travel_to Time.zone.parse("2026-07-02 21:00:00") do
      goal = create(
        :chess_com_goal,
        :recurring,
        check_time_minutes: 20 * 60,
        deadline_at: Time.zone.parse("2026-07-10 20:00:00")
      )
      goal.update_columns(last_check_status: "passed")

      expect(goal.due_at_or_before(Time.current)).to be_nil
    end
  end

  it "returns an interval due_at after the first slot elapses" do
    travel_to Time.zone.parse("2026-07-02 10:35:00") do
      goal = create(
        :chess_com_goal,
        :interval_recurring,
        interval_minutes: 30,
        deadline_at: Time.zone.parse("2026-07-10 20:00:00")
      )
      goal.update_columns(created_at: Time.zone.parse("2026-07-02 10:00:00"), updated_at: Time.zone.parse("2026-07-02 10:00:00"))

      due_at = goal.due_at_or_before(Time.current)
      expect(due_at).to eq(Time.zone.parse("2026-07-02 10:30:00"))
    end
  end

  it "returns the next interval slot for preview before the first check is due" do
    travel_to Time.zone.parse("2026-07-02 10:15:00") do
      goal = create(
        :chess_com_goal,
        :interval_recurring,
        interval_minutes: 30,
        deadline_at: Time.zone.parse("2026-07-10 20:00:00")
      )
      goal.update_columns(created_at: Time.zone.parse("2026-07-02 10:00:00"), updated_at: Time.zone.parse("2026-07-02 10:00:00"))

      expect(goal.due_at_or_before(Time.current)).to be_nil
      expect(goal.preview_check_due_at).to eq(Time.zone.parse("2026-07-02 10:30:00"))
      expect(goal.manual_check_due_at).to eq(Time.zone.parse("2026-07-02 10:15:00"))
    end
  end

  it "returns the deadline for preview before it is due in deadline mode" do
    deadline = 10.days.from_now.change(sec: 0)
    goal = create(:chess_com_goal, deadline_at: deadline)

    expect(goal.due_at_or_before(Time.current)).to be_nil
    expect(goal.preview_check_due_at).to eq(deadline)
  end
end
