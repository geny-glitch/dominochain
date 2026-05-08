# frozen_string_literal: true

FactoryBot.define do
  factory :chaster_time_event do
    association :user
    chaster_lock_id { "lock-#{SecureRandom.hex(4)}" }
    source { "api" }
    seconds { 300 }
    summary { "Ajout de temps" }
    metadata { {} }
    occurred_at { Time.current }
  end
end
