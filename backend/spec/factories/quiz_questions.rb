# frozen_string_literal: true

FactoryBot.define do
  factory :quiz_question do
    question { "Quelle est la capitale de la France ?" }
    answers { ["Paris"] }
    difficulty { "bleu" }
    question_type { "normal" }
  end
end
