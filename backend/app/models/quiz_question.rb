# frozen_string_literal: true

class QuizQuestion < ApplicationRecord
  DIFFICULTIES = %w[bleu blanc rouge].freeze
  QUESTION_TYPES = %w[normal banco super_banco].freeze

  validates :question, presence: true
  validates :difficulty, inclusion: { in: DIFFICULTIES }
  validates :question_type, inclusion: { in: QUESTION_TYPES }
  validate :answers_present

  scope :normal, -> { where(question_type: "normal") }
  scope :banco, -> { where(question_type: "banco") }
  scope :super_banco, -> { where(question_type: "super_banco") }
  scope :by_difficulty, ->(d) { where(difficulty: d) }

  def self.random_set(difficulties:)
    return [] if difficulties.blank?

    ids = []
    difficulties.tally.each do |diff, count|
      ids.concat(by_difficulty(diff).normal.order(Arel.sql("RANDOM()")).limit(count).pluck(:id))
    end
    where(id: ids).order(Arel.sql("RANDOM()"))
  end

  def self.random_banco
    banco.order(Arel.sql("RANDOM()")).first
  end

  def self.random_super_banco
    super_banco.order(Arel.sql("RANDOM()")).first
  end

  def display_question
    question.gsub(/\s*\[v[a-f0-9]+\]\z/, "")
  end

  def correct?(answer)
    return false if answer.blank?

    normalized = normalize_answer(answer.to_s)
    answers.any? { |a| normalize_answer(a.to_s) == normalized }
  end

  # Normalise pour comparaison : insensible à la casse, accents, tirets, apostrophes
  def self.normalize_answer(str)
    return "" if str.blank?

    str.to_s.strip
      .downcase
      .gsub("œ", "oe")
      .gsub("æ", "ae")
      .unicode_normalize(:nfd)
      .gsub(/\p{Mn}/, "")       # accents (é→e, à→a, etc.)
      .tr("-'’`\u2019", " ")    # apostrophes, tirets
      .gsub(/\s+/, "")
      .strip
  end

  def normalize_answer(str)
    self.class.normalize_answer(str)
  end

  private

  def answers_present
    errors.add(:answers, "doit contenir au moins une réponse") if answers.blank? || !answers.is_a?(Array)
  end
end
