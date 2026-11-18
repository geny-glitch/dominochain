# frozen_string_literal: true

require "rails_helper"

RSpec.describe ZapProgram, type: :model do
  let(:beta) { create(:user, :beta) }

  before do
    stub_beta_catalog_feature_flags
    enable_pishock_catalog!(beta)
    beta.update!(public_pishock_enabled: true)
  end

  describe ".find_or_create_for!" do
    it "creates one public program per beta" do
      first = described_class.find_or_create_for!(beta: beta, source: "public")
      second = described_class.find_or_create_for!(beta: beta, source: "public")
      expect(first.id).to eq(second.id)
      expect(first.source).to eq("public")
    end

    it "requires a boss for boss source" do
      boss = create(:user, :boss)
      program = described_class.find_or_create_for!(beta: beta, source: "boss", boss: boss)
      expect(program.boss).to eq(boss)
    end
  end

  describe "#disarm!" do
    it "bumps generation and clears busy_until" do
      program = create(:zap_program, :armed, beta: beta, busy_until: 1.minute.from_now, generation: 3)
      program.disarm!
      expect(program.reload.armed?).to be false
      expect(program.generation).to eq(4)
      expect(program.busy_until).to be_nil
    end
  end

  describe "#claim_busy!" do
    it "prevents overlapping claims" do
      program = create(:zap_program, beta: beta)
      expect(program.claim_busy!(30)).to be true
      expect(program.claim_busy!(30)).to be false
    end
  end

  describe "#delivery_allowed?" do
    it "requires an accepted control for boss programs" do
      boss = create(:user, :boss)
      program = create(:zap_program, :boss, beta: beta, boss: boss)
      expect(program.delivery_allowed?).to be false
      create(:control, boss: boss, beta: beta, status: :accepted)
      expect(program.reload.delivery_allowed?).to be true
    end

    it "requires the public page for public programs" do
      program = create(:zap_program, beta: beta)
      expect(program.delivery_allowed?).to be true
      beta.update!(public_pishock_enabled: false)
      expect(program.delivery_allowed?).to be false
    end
  end
end
