# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChessComGoalEvaluator do
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
  let(:chess_com_service) { instance_double(ChessComService) }
  let(:chaster_service) { instance_double(ChasterService) }
  let(:evaluator) do
    described_class.new(user, chess_com_service: chess_com_service, chaster_service: chaster_service)
  end

  before do
    stub_beta_catalog_feature_flags("beta_source_chess" => true, "beta_action_chaster" => true)
    user.update!(
      beta_ui_prefs: user.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "chess" => true }, "actions" => { "chaster" => true } }
      )
    )
  end

  def create_past_deadline_goal(**attrs)
    goal = create(:chess_com_goal, user: user, deadline_at: 30.days.from_now, **attrs.except(:deadline_at))
    goal.update_columns(deadline_at: attrs[:deadline_at]) if attrs.key?(:deadline_at)
    goal
  end

  def assign_any_goal_failed!(seconds:)
    config = user.ensure_chess_com_config!
    config.assign_scenarios!(
      ScenarioSet.new(
        scenarios: [
          ScenarioSet::Scenario.new(
            id: SecureRandom.uuid,
            event: "any_goal_failed",
            trigger: {},
            actions: [
              {
                possibility_id: "chaster.add_time",
                config: BetaEvents::ActionRegistry.normalize_config(
                  "chaster.add_time",
                  { "seconds" => seconds }
                )
              }
            ]
          )
        ]
      )
    )
    config.save!
  end

  describe "#evaluate_goal!" do
    it "passes when current rating meets the target" do
      goal = create(:chess_com_goal, user: user, target_rating: 1500, deadline_at: 10.days.from_now)
      allow(chess_com_service).to receive(:current_rating_for!).with("tester", "blitz").and_return(1510)

      check = evaluator.evaluate_goal!(goal)

      expect(check.status).to eq("passed")
      expect(check.rating_at_check).to eq(1510)
      expect(check.target_rating).to eq(1500)
      expect(check.chaster_applied).to be false
      expect(goal.reload.last_check_status).to eq("passed")
    end

    it "fails and applies Chaster when rating is below target" do
      goal = create(:chess_com_goal, user: user, target_rating: 1500, deadline_at: 10.days.from_now)
      assign_any_goal_failed!(seconds: 1800)
      allow(chess_com_service).to receive(:current_rating_for!).with("tester", "blitz").and_return(1400)
      allow(ChasterService).to receive(:new).with(user).and_return(chaster_service)
      allow(chaster_service).to receive(:current_lock).and_return({ id: "lock-chess" })
      allow(chaster_service).to receive(:add_time_to_lock)

      first = evaluator.evaluate_goal!(goal)
      second = evaluator.evaluate_goal!(goal)

      expect(first.status).to eq("failed")
      expect(first.chaster_applied).to be true
      expect(first.chaster_lock_id).to eq("lock-chess")
      expect(chaster_service).to have_received(:add_time_to_lock).once.with(
        "lock-chess",
        1800,
        source: "chess_com_goal",
        summary: I18n.t("chaster.time_events.summaries.chess_com_goal", goal_title: goal.name),
        metadata: hash_including("goal_id" => goal.id, "goal_title" => goal.name)
      )
      expect(second.id).to eq(first.id)
      expect(goal.chess_com_goal_checks.count).to eq(1)
    end

    it "evaluates due goals past their deadline" do
      travel_to Time.zone.parse("2026-07-02 10:00:00") do
        due_goal = create_past_deadline_goal(deadline_at: Time.zone.parse("2026-07-01 12:00:00"))
        create(:chess_com_goal, user: user, deadline_at: Time.zone.parse("2026-07-10 12:00:00"))
        allow(chess_com_service).to receive(:current_rating_for!).and_return(1600)

        checks = evaluator.evaluate_due_goals!

        expect(checks.map(&:chess_com_goal_id)).to eq([ due_goal.id ])
      end
    end

    it "applies sanctions on each failed daily check in recurring mode" do
      travel_to Time.zone.parse("2026-07-02 21:00:00") do
        goal = create(
          :chess_com_goal,
          :recurring,
          user: user,
          target_rating: 1500,
          check_time_minutes: 20 * 60,
          deadline_at: Time.zone.parse("2026-07-10 20:00:00")
        )
        assign_any_goal_failed!(seconds: 900)
        allow(chess_com_service).to receive(:current_rating_for!).with("tester", "blitz").and_return(1400)
        allow(ChasterService).to receive(:new).with(user).and_return(chaster_service)
        allow(chaster_service).to receive(:current_lock).and_return({ id: "lock-chess" })
        allow(chaster_service).to receive(:add_time_to_lock)

        first = evaluator.evaluate_goal!(goal)

        travel 1.day
        second = evaluator.evaluate_goal!(goal)

        expect(first.status).to eq("failed")
        expect(second.status).to eq("failed")
        expect(goal.chess_com_goal_checks.count).to eq(2)
        expect(chaster_service).to have_received(:add_time_to_lock).twice
      end
    end

    it "stops recurring checks after the goal is passed" do
      travel_to Time.zone.parse("2026-07-02 21:00:00") do
        goal = create(
          :chess_com_goal,
          :recurring,
          user: user,
          target_rating: 1500,
          check_time_minutes: 20 * 60,
          deadline_at: Time.zone.parse("2026-07-10 20:00:00")
        )
        allow(chess_com_service).to receive(:current_rating_for!).and_return(1600)

        check = evaluator.evaluate_goal!(goal)
        checks = evaluator.evaluate_due_goals!

        expect(check.status).to eq("passed")
        expect(checks).to eq([])
      end
    end

    it "applies sanctions on each failed interval check" do
      travel_to Time.zone.parse("2026-07-02 11:05:00") do
        goal = create(
          :chess_com_goal,
          :interval_recurring,
          user: user,
          target_rating: 1500,
          interval_minutes: 30,
          deadline_at: Time.zone.parse("2026-07-10 20:00:00")
        )
        goal.update_columns(created_at: Time.zone.parse("2026-07-02 10:00:00"), updated_at: Time.zone.parse("2026-07-02 10:00:00"))
        assign_any_goal_failed!(seconds: 600)
        allow(chess_com_service).to receive(:current_rating_for!).with("tester", "blitz").and_return(1400)
        allow(ChasterService).to receive(:new).with(user).and_return(chaster_service)
        allow(chaster_service).to receive(:current_lock).and_return({ id: "lock-chess" })
        allow(chaster_service).to receive(:add_time_to_lock)

        check = evaluator.evaluate_due_goal!(goal)

        expect(goal.chess_com_goal_checks.count).to eq(2)
        expect(chaster_service).to have_received(:add_time_to_lock).twice
        expect(check.status).to eq("failed")
      end
    end
  end

  describe "#preview_goal" do
    it "returns status without persisting a check" do
      goal = create(:chess_com_goal, user: user, target_rating: 1500, deadline_at: 10.days.from_now)
      allow(chess_com_service).to receive(:current_rating_for!).and_return(1490)

      preview = evaluator.preview_goal(goal)

      expect(preview[:status]).to eq("failed")
      expect(preview[:rating_at_check]).to eq(1490)
      expect(preview[:due_at]).to be_present
      expect(goal.chess_com_goal_checks.count).to eq(0)
    end

    it "works before the first interval check is due" do
      travel_to Time.zone.parse("2026-07-02 10:15:00") do
        goal = create(
          :chess_com_goal,
          :interval_recurring,
          user: user,
          target_rating: 1500,
          interval_minutes: 30,
          deadline_at: Time.zone.parse("2026-07-10 20:00:00")
        )
        goal.update_columns(created_at: Time.zone.parse("2026-07-02 10:00:00"), updated_at: Time.zone.parse("2026-07-02 10:00:00"))
        allow(chess_com_service).to receive(:current_rating_for!).with("tester", "blitz").and_return(1490)

        preview = evaluator.preview_goal(goal)

        expect(preview[:due_at]).to eq(Time.zone.parse("2026-07-02 10:30:00").utc)
        expect(preview[:status]).to eq("failed")
        expect(goal.chess_com_goal_checks.count).to eq(0)
      end
    end
  end
end
