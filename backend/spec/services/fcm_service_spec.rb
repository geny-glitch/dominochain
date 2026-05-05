# frozen_string_literal: true

require "rails_helper"

RSpec.describe FcmService do
  describe ".send_showcase_game_started_notification" do
    it "sends a game-start payload" do
      device = create(:device, fcm_token: "fcm-token")
      allow(described_class).to receive(:send_showcase_game_started_notification).and_call_original
      allow(described_class).to receive(:credentials_configured?).and_return(true)
      allow(described_class).to receive(:send_request)

      described_class.send_showcase_game_started_notification(
        device: device,
        game_session_id: 123,
        game_type: "snake"
      )

      expect(described_class).to have_received(:send_request) do |sent_device, payload|
        expect(sent_device).to eq(device)
        message = payload.fetch(:message)
        expect(message[:token]).to eq("fcm-token")
        expect(message[:notification]).to eq(
          title: "OTB",
          body: "Quelqu'un commence une partie de Snake."
        )
        expect(message[:data]).to eq(
          type: "showcase_game_started",
          game_session_id: "123",
          game_type: "snake"
        )
        expect(message[:android]).to eq(priority: "high")
      end
    end
  end
end
