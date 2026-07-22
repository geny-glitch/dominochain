# frozen_string_literal: true

class ChessComGoalCheckJob < ApplicationJob
  def perform(goal_id = nil, due_at = nil)
    due_at = due_at.present? ? Time.zone.parse(due_at.to_s) : Time.current
    scope = goal_id.present? ? ChessComGoal.where(id: goal_id) : ChessComGoal.due_for_check(due_at)

    scope.includes(:user).find_each do |goal|
      next unless goal.user.chess_com_verified?

      ChessComGoalEvaluator.new(goal.user).evaluate_due_goal!(goal, now: due_at)
    rescue ChessComService::Error, ChasterService::Error => e
      Rails.logger.warn("ChessComGoalCheckJob goal=#{goal.id} failed: #{e.class}: #{e.message}")
    end
  end
end
