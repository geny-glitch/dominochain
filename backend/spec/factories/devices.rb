# frozen_string_literal: true

FactoryBot.define do
  factory :device do
    association :user
    sequence(:device_id) { |n| "device-#{n}-#{SecureRandom.hex(8)}" }
    auth_token { SecureRandom.hex(32) }
    screen_width { 1080 }
    screen_height { 1920 }

    trait :without_user do
      user { nil }
    end
  end
end
