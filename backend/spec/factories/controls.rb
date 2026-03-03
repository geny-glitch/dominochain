# frozen_string_literal: true

FactoryBot.define do
  factory :control do
    association :boss, factory: :user, traits: [:boss]
    association :beta, factory: :user, traits: [:beta]
    status { :accepted }

    trait :pending do
      status { :pending }
    end

    trait :released do
      status { :released }
    end
  end
end
