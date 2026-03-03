# frozen_string_literal: true

FactoryBot.define do
  factory :task do
    association :device
    name { "Test task" }
    description { "Test description" }
    deadline_at { 1.day.from_now }
    status { "pending" }

    trait :with_proof do
      after(:create) do |task|
        create(:proof_of_completion, task: task)
      end
    end
  end
end
