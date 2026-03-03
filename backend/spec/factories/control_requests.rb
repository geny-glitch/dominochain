# frozen_string_literal: true

FactoryBot.define do
  factory :control_request do
    association :beta, factory: :user, traits: [:beta]
    association :boss, factory: :user, traits: [:boss]
    status { :pending }

    trait :accepted do
      status { :accepted }
    end

    trait :rejected do
      status { :rejected }
    end
  end
end
