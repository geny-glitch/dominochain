# frozen_string_literal: true

FactoryBot.define do
  factory :zap_program do
    beta { association :user, :beta }
    source { "public" }
    armed { false }
    generation { 0 }

    trait :boss do
      source { "boss" }
      boss { association :user, :boss }
    end

    trait :armed do
      armed { true }
    end
  end

  factory :zap_slot do
    zap_program
    schedule_kind { "daily" }
    time_of_day_minutes { 8 * 60 }
    pattern_kind { "single" }
    intensity { 40 }
    duration { 2 }
    position { 0 }

    trait :once do
      schedule_kind { "once" }
      time_of_day_minutes { nil }
      fires_at { 1.day.from_now.change(min: 0, sec: 0) }
    end

    trait :interval do
      schedule_kind { "interval" }
      time_of_day_minutes { nil }
      interval_minutes { 45 }
      window_start_minutes { 10 * 60 }
      window_end_minutes { 20 * 60 }
    end

    trait :roulette do
      pattern_kind { "roulette" }
      intensity { nil }
      count { 4 }
      intensity_min { 15 }
      intensity_max { 80 }
      duration { 1 }
    end

    trait :burst do
      pattern_kind { "burst" }
      count { 5 }
      intensity { 50 }
      gap_seconds { 2 }
      duration { 1 }
    end
  end
end
