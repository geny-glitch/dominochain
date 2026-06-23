# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:nickname) { |n| "user#{n}" }
    sequence(:email) { |n| "user#{n}@dominochain.app" }
    password { "password123" }
    password_confirmation { "password123" }
    role { :beta }

    trait :boss do
      role { :boss }
    end

    trait :admin do
      role { :admin }
    end

    trait :beta do
      role { :beta }
    end
  end
end
