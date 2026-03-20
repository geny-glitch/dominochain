# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuizQuestion, type: :model do
  describe ".normalize_answer" do
    it "met en minuscules" do
      expect(described_class.normalize_answer("PARIS")).to eq("paris")
    end

    it "supprime les accents" do
      expect(described_class.normalize_answer("cœur")).to eq("coeur")
      expect(described_class.normalize_answer("Éléphant")).to eq("elephant")
    end

    it "ignore les tirets et apostrophes" do
      expect(described_class.normalize_answer("Jean-Pierre")).to eq("jeanpierre")
      expect(described_class.normalize_answer("l'homme")).to eq("lhomme")
    end

    it "supprime les espaces superflus" do
      expect(described_class.normalize_answer("  Paris  ")).to eq("paris")
    end
  end

  describe "#correct?" do
    let(:question) do
      create(:quiz_question, answers: ["Paris", "paris"])
    end

    it "accepte la casse" do
      expect(question.correct?("PARIS")).to be true
      expect(question.correct?("paris")).to be true
    end

    it "accepte sans accents" do
      q = create(:quiz_question, answers: ["cœur"])
      expect(q.correct?("coeur")).to be true
      expect(q.correct?("CŒUR")).to be true
    end

    it "accepte sans tirets ni apostrophes" do
      q = create(:quiz_question, answers: ["Jean-Pierre"])
      expect(q.correct?("Jean Pierre")).to be true
      expect(q.correct?("JeanPierre")).to be true
    end

    it "rejette les réponses vides" do
      expect(question.correct?("")).to be false
      expect(question.correct?(nil)).to be false
    end
  end
end
