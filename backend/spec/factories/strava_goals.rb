# frozen_string_literal: true

FactoryBot.define do
  factory :strava_goal do
    association :user
    name { "Cardio weekly" }
    enabled { true }
    weekly_required_count { 2 }
    min_duration_seconds { 30.minutes.to_i }
    min_calories { nil }
    activity_types { ["Run"] }
    device_names { [] }
    chaster_penalty_seconds { 2.hours.to_i }
  end
end
