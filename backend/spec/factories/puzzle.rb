# frozen_string_literal: true

FactoryBot.define do
  factory :puzzle_config do
    user
    default_piece_count { 25 }
    default_reference_mode { "blurred" }
    cooldown_seconds { 0 }
    scenarios { { "scenarios" => [] } }
  end

  factory :puzzle_session do
    user
    status { "assigned" }
    origin { "self" }
    image_source { "leverage_photo" }
    association :leverage_photo, factory: [:leverage_photo, :with_images]
    piece_count { 9 }
    grid_cols { 3 }
    grid_rows { 3 }
    pieces_total { 9 }
    pieces_placed { 0 }
    reference_mode { "blurred" }
    layout_seed { 12_345 }
    config_snapshot { {} }

    trait :active do
      status { "active" }
      started_at { Time.current }
    end

    trait :with_time_limit do
      time_limit_seconds { 600 }
      deadline_at { 10.minutes.from_now }
    end
  end

  factory :puzzle_session_event do
    association :puzzle_session
    kind { "completed" }
    pieces_placed { 9 }
    pieces_total { 9 }
    actions_executed { [] }
    occurred_at { Time.current }
  end
end
