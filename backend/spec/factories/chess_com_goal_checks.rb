# frozen_string_literal: true

FactoryBot.define do
  factory :chess_com_goal_check do
    association :chess_com_goal
    user { chess_com_goal.user }
    due_at { chess_com_goal.deadline_at }
    rating_type { chess_com_goal.rating_type }
    target_rating { chess_com_goal.target_rating }
    baseline_rating { chess_com_goal.baseline_rating }
    rating_at_check { chess_com_goal.target_rating }
    status { "passed" }
    checked_at { Time.current }
    details { {} }
  end
end
