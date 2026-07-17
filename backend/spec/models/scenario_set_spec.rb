# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScenarioSet do
  describe ".from_legacy_config" do
    it "builds scenarios only for active sanctions using raw columns" do
      config = build(
        :wallpaper_enforcement_config,
        mismatch_delay_minutes: 45,
        mismatch_sanction_mode: WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK,
        mismatch_sanction: {
          "items" => [
            { "possibility_id" => "chaster.add_time", "enabled" => true, "config" => { "seconds" => 600 } }
          ]
        },
        permissions_lost_sanction: { "items" => [] },
        app_unreachable_sanction: { "items" => [] }
      )

      set = described_class.from_legacy_config(config)

      expect(set.scenarios.size).to eq(1)
      scenario = set.for_event("mismatch")
      expect(scenario.delay_minutes).to eq(45)
      expect(scenario.mode).to eq(WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK)
      expect(scenario.actions.first[:possibility_id]).to eq("chaster.add_time")
      expect(scenario.actions.first[:config][:seconds]).to eq(600)
    end
  end

  describe ".from_params" do
    it "coerces indexed hashes into scenario arrays" do
      set = described_class.from_params(
        {
          "scenarios" => {
            "0" => {
              "id" => "abc",
              "event" => "mismatch",
              "trigger" => { "delay_minutes" => "15", "mode" => "strict" },
              "actions" => {
                "0" => {
                  "possibility_id" => "chaster.add_time",
                  "config" => { "seconds" => "120" }
                }
              }
            }
          }
        }
      )

      expect(set.scenarios.size).to eq(1)
      scenario = set.scenarios.first
      expect(scenario.event).to eq("mismatch")
      expect(scenario.delay_minutes).to eq(15)
      expect(scenario.actions.first[:config][:seconds]).to eq(120)
    end

    it "returns empty for blank params" do
      expect(described_class.from_params(nil).scenarios).to eq([])
    end
  end

  describe "#to_sanction_set" do
    it "marks actions as enabled" do
      set = described_class.from_hash(
        {
          "scenarios" => [
            {
              "id" => "1",
              "event" => "permissions_lost",
              "trigger" => { "delay_minutes" => 0 },
              "actions" => [
                { "possibility_id" => "pishock.shock", "config" => { "intensity" => 40, "duration" => 2 } }
              ]
            }
          ]
        }
      )

      sanction = set.for_event("permissions_lost").to_sanction_set
      expect(sanction.enabled?("pishock.shock")).to be true
      expect(sanction.item_for("pishock.shock").config[:intensity]).to eq(40)
    end
  end
end
