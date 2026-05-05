# frozen_string_literal: true

FactoryBot.define do
  factory :strava_goal do
    association :user
    name { "Cardio rolling" }
    enabled { true }
    required_activity_count { 2 }
    window_days { 7 }
    check_time_minutes { 0 }
    time_zone { "Europe/Paris" }
    min_duration_seconds { 30.minutes.to_i }
    min_calories { nil }
    activity_types { [ "Run" ] }
    device_names { [] }
    chaster_penalty_seconds { 2.hours.to_i }
  end
end
