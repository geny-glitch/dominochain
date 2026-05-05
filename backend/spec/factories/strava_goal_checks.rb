# frozen_string_literal: true

FactoryBot.define do
  factory :strava_goal_check do
    association :strava_goal
    user { strava_goal.user }
    week_start_on { Date.current.beginning_of_week(:monday) - 1.week }
    week_end_on { week_start_on + 6.days }
    required_count { strava_goal.weekly_required_count }
    valid_count { 0 }
    total_count { 0 }
    status { "failed" }
    chaster_penalty_seconds { strava_goal.chaster_penalty_seconds }
    checked_at { Time.current }
  end
end
