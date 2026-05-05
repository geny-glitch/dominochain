# frozen_string_literal: true

class StravaGoalCheckJob < ApplicationJob
  def perform(goal_id = nil, due_at = nil)
    due_at = due_at.present? ? Time.zone.parse(due_at.to_s) : Time.current
    scope = goal_id.present? ? StravaGoal.where(id: goal_id) : StravaGoal.due_for_check(due_at)

    scope.includes(:user).find_each do |goal|
      goal_due_at = goal_id.present? ? due_at : goal.due_at_or_before(due_at)
      next unless goal_due_at

      StravaGoalEvaluator.new(goal.user).evaluate_goal!(goal, due_at: goal_due_at)
    rescue StravaService::Error, ChasterService::Error => e
      Rails.logger.warn("StravaGoalCheckJob goal=#{goal.id} failed: #{e.class}: #{e.message}")
    end
  end
end
