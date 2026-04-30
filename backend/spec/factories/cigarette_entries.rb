# frozen_string_literal: true

FactoryBot.define do
  factory :cigarette_entry do
    association :user
    count { 1 }
    smoked_at { Time.current }
    smoked_on { smoked_at.to_date }
    chaster_seconds { 300 }
    chaster_applied { false }
  end
end
