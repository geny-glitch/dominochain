FactoryBot.define do
  factory :game_session do
    user { nil }
    game_type { "MyString" }
    played_at { "2026-03-20 14:29:16" }
    score { 1 }
    player_name { "MyString" }
  end
end
