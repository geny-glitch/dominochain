# frozen_string_literal: true

require "rails_helper"

RSpec.describe FcmService do
  describe ".send_new_task_notification" do
    it "uses the staging notification title when BG_ENV is staging" do
      previous_bg_env = ENV["BG_ENV"]
      ENV["BG_ENV"] = "staging"
      device = instance_double(Device, fcm_token: "fcm-token", device_id: "device-id")
      task = instance_double(Task, name: "Ranger la chambre", id: 123)
      allow(described_class).to receive(:send_new_task_notification).and_call_original
      allow(described_class).to receive(:credentials_configured?).and_return(true)
      allow(described_class).to receive(:send_request)

      described_class.send_new_task_notification(
        device: device,
        task: task,
        trigger_alarm: false
      )

      expect(described_class).to have_received(:send_request) do |_sent_device, payload|
        expect(payload.dig(:message, :data, :title)).to eq("Domino Chain dev")
      end
    ensure
      if previous_bg_env.nil?
        ENV.delete("BG_ENV")
      else
        ENV["BG_ENV"] = previous_bg_env
      end
    end
  end

  describe ".send_showcase_game_started_notification" do
    it "sends a game-start payload" do
      device = create(:device, fcm_token: "fcm-token")
      allow(described_class).to receive(:send_showcase_game_started_notification).and_call_original
      allow(described_class).to receive(:credentials_configured?).and_return(true)
      allow(described_class).to receive(:send_request)

      described_class.send_showcase_game_started_notification(
        device: device,
        game_session_id: 123,
        game_type: "snake",
        player_name: "Alice"
      )

      expect(described_class).to have_received(:send_request) do |sent_device, payload|
        expect(sent_device).to eq(device)
        message = payload.fetch(:message)
        expect(message[:token]).to eq("fcm-token")
        expect(message[:notification]).to eq(
          title: "Domino Chain",
          body: "Alice commence une partie de Snake."
        )
        expect(message[:data]).to eq(
          type: "showcase_game_started",
          game_session_id: "123",
          game_type: "snake",
          player_name: "Alice"
        )
        expect(message[:android]).to eq(priority: "high")
      end
    end

    it "keeps the generic start payload when no player name is available" do
      device = create(:device, fcm_token: "fcm-token")
      allow(described_class).to receive(:send_showcase_game_started_notification).and_call_original
      allow(described_class).to receive(:credentials_configured?).and_return(true)
      allow(described_class).to receive(:send_request)

      described_class.send_showcase_game_started_notification(
        device: device,
        game_session_id: 123,
        game_type: "snake"
      )

      expect(described_class).to have_received(:send_request) do |_sent_device, payload|
        message = payload.fetch(:message)
        expect(message[:notification]).to eq(
          title: "Domino Chain",
          body: "Quelqu'un commence une partie de Snake."
        )
        expect(message[:data]).to eq(
          type: "showcase_game_started",
          game_session_id: "123",
          game_type: "snake"
        )
      end
    end
  end

  describe ".send_wallpaper_check_result_notification" do
    it "sends a wallpaper check result payload" do
      device = create(:device, fcm_token: "fcm-token")
      check = device.user.wallpaper_compliance_checks.create!(
        device: device,
        status: "verified",
        check_kind: "scheduled",
        similarity_score: 0.95,
        checked_at: Time.current
      )
      allow(described_class).to receive(:send_wallpaper_check_result_notification).and_call_original
      allow(described_class).to receive(:credentials_configured?).and_return(true)
      allow(described_class).to receive(:send_request)

      described_class.send_wallpaper_check_result_notification(
        device: device,
        check: check,
        title: "Wallpaper check",
        body: "Verified ✓ · 95% match"
      )

      expect(described_class).to have_received(:send_request) do |sent_device, payload|
        expect(sent_device).to eq(device)
        message = payload.fetch(:message)
        expect(message[:token]).to eq("fcm-token")
        expect(message[:notification]).to eq(
          title: "Wallpaper check",
          body: "Verified ✓ · 95% match"
        )
        expect(message[:data]).to include(
          type: "wallpaper_check_result",
          title: "Wallpaper check",
          body: "Verified ✓ · 95% match",
          check_id: check.id.to_s,
          status: "verified",
          similarity_score: "0.95",
          check_kind: "scheduled"
        )
        expect(message[:android]).to eq(priority: "high")
      end
    end
  end
end
