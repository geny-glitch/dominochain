# frozen_string_literal: true

class StravaGoalCheckJob < ApplicationJob
  def perform(user_id = nil, week_start_on = nil)
    scope = user_id.present? ? User.where(id: user_id) : User.where.not(strava_access_token: nil)
    week_start_on = week_start_on.present? ? Date.parse(week_start_on.to_s) : StravaGoalEvaluator.previous_week_start_on

    scope.find_each do |user|
      StravaGoalEvaluator.new(user).evaluate_enabled_goals!(week_start_on: week_start_on)
    rescue StravaService::Error, ChasterService::Error => e
      Rails.logger.warn("StravaGoalCheckJob user=#{user.id} failed: #{e.class}: #{e.message}")
    end
  end
end
