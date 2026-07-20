# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuryfiConfig do
  let(:user) { create(:user, :beta) }

  describe ".shock_level_for_label" do
    it "returns 0 by default" do
      expect(described_class.shock_level_for_label(user, 0)).to eq(0)
    end

    it "clamps stored values to 0..3" do
      user.update!(puryfi_shock_level_per_label: { "0" => 5, "1" => -2 })
      expect(described_class.shock_level_for_label(user, 0)).to eq(3)
      expect(described_class.shock_level_for_label(user, 1)).to eq(0)
    end
  end

  describe ".pishock_params_for_level" do
    it "returns nil for level 0" do
      expect(described_class.pishock_params_for_level(user, 0)).to be_nil
    end

    it "returns default intensity and duration for level 2" do
      expect(described_class.pishock_params_for_level(user, 2)).to eq(
        intensity: 30,
        duration: 1
      )
    end

    it "applies the global intensity factor" do
      user.update!(pishock_intensity_factor: 2)
      expect(described_class.pishock_params_for_level(user, 1)).to eq(
        intensity: 20,
        duration: 1
      )
    end
  end

  describe ".sanitize_shock_level_per_label" do
    it "merges incoming label levels" do
      user.update!(puryfi_shock_level_per_label: { "0" => 1 })
      merged = described_class.sanitize_shock_level_per_label({ "0" => 3, "2" => 9 }, existing: user.puryfi_shock_level_per_label)
      expect(merged).to include("0" => 3, "2" => 3)
    end
  end
end
