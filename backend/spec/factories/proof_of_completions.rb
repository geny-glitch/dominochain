# frozen_string_literal: true

FactoryBot.define do
  factory :proof_of_completion do
    association :task
    text { "Proof text" }
    status { "pending" }

    trait :accepted do
      status { "accepted" }
    end

    trait :rejected do
      status { "rejected" }
    end
  end
end
