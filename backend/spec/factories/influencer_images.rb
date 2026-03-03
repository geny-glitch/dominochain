# frozen_string_literal: true

FactoryBot.define do
  factory :influencer_image do
    sequence(:url) { |n| "https://example.com/image-#{n}.jpg" }
    sequence(:name) { |n| "influencer_#{n}" }
    source { "wikimedia" }
  end
end
