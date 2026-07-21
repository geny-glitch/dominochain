# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminStatsQuery do
  describe ".call" do
    it "returns total users and users active today from device activity" do
      create(:user, :admin)
      active_beta = create(:user, :beta)
      inactive_beta = create(:user, :beta)
      create(:device, user: active_beta, last_seen_at: Time.current)
      create(:device, user: inactive_beta, last_seen_at: 2.days.ago)

      result = described_class.call

      expect(result.total_users).to eq(3)
      expect(result.users_active_today).to eq(1)
    end

    it "counts active scenario consequences per source-action pair" do
      beta = create(:user, :beta)
      create(
        :wallpaper_enforcement_config,
        user: beta,
        enabled: true,
        scenarios: {
          "scenarios" => [
            {
              "id" => SecureRandom.uuid,
              "event" => "mismatch",
              "trigger" => { "delay_minutes" => 30, "mode" => "strict" },
              "actions" => [
                { "possibility_id" => "chaster.add_time", "config" => { "seconds" => 3600 } }
              ]
            }
          ]
        }
      )

      result = described_class.call
      row = result.consequence_counts.find { |entry| entry.source == "wallpaper" && entry.possibility_id == "chaster.add_time" }

      expect(row.count).to eq(1)
    end

    it "ignores wallpaper consequences when enforcement is disabled" do
      beta = create(:user, :beta)
      create(
        :wallpaper_enforcement_config,
        user: beta,
        enabled: false,
        scenarios: {
          "scenarios" => [
            {
              "id" => SecureRandom.uuid,
              "event" => "mismatch",
              "trigger" => { "delay_minutes" => 30, "mode" => "strict" },
              "actions" => [
                { "possibility_id" => "chaster.add_time", "config" => { "seconds" => 3600 } }
              ]
            }
          ]
        }
      )

      result = described_class.call
      wallpaper_rows = result.consequence_counts.select { |entry| entry.source == "wallpaper" }

      expect(wallpaper_rows).to be_empty
    end

    it "counts fixed puryfi consequences" do
      create(:user, :beta, puryfi_seconds_per_label: { "0" => 120 })

      result = described_class.call
      row = result.consequence_counts.find { |entry| entry.source == "puryfi" && entry.possibility_id == "chaster.add_time" }

      expect(row.count).to eq(1)
    end
  end
end
