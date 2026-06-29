# frozen_string_literal: true

FactoryBot.define do
  factory :device_wallpaper_sample do
    association :device
    sampled_at { Time.current }
    verification_status { "pending" }
  end
end
