# frozen_string_literal: true

FactoryBot.define do
  factory :strava_goal_check do
    association :strava_goal
    user { strava_goal.user }
    due_at { Time.current.change(sec: 0) }
    period_start_at { due_at - strava_goal.window_days.days }
    period_end_at { due_at }
    window_days { strava_goal.window_days }
    check_time_minutes { strava_goal.check_time_minutes }
    time_zone { strava_goal.time_zone }
    required_count { strava_goal.required_count }
    valid_count { 0 }
    total_count { 0 }
    status { "failed" }
    chaster_penalty_seconds { strava_goal.chaster_penalty_seconds }
    checked_at { Time.current }
  end
end
