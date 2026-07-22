# frozen_string_literal: true

FactoryBot.define do
  factory :chess_com_goal do
    association :user
    name { "Reach 1500 blitz" }
    enabled { true }
    rating_type { "blitz" }
    target_rating { 1500 }
    baseline_rating { 1200 }
    deadline_at { 30.days.from_now }
    time_zone { "Europe/Paris" }

    trait :recurring do
      schedule_mode { "recurring" }
      recurrence_kind { "daily" }
      check_time_minutes { 20 * 60 }
    end

    trait :interval_recurring do
      schedule_mode { "recurring" }
      recurrence_kind { "interval" }
      interval_minutes { 30 }
      check_time_minutes { nil }
    end
  end
end
