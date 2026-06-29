# frozen_string_literal: true

FactoryBot.define do
  factory :device_screenshot do
    association :device
    captured_at { Time.current }
    verification_status { "pending" }
  end
end
