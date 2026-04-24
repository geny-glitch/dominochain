# frozen_string_literal: true

FactoryBot.define do
  factory :game_session do
    user
    game_type { "snake" }
    played_at { Time.current }
    score { 0 }
    player_name { nil }
  end
end
