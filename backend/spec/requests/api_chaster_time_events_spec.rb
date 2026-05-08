# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API Chaster time events", type: :request do
  let(:beta) { create(:user, :beta) }
  let(:device) { create(:device, user: beta) }
  let(:headers) { { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token } }

  describe "GET /api/chaster/time_events" do
    it "returns Chaster timer modifications paginated newest first" do
      travel_to Time.zone.parse("2026-05-08 09:00:00") do
        create(:chaster_time_event, user: beta, seconds: 60, source: "api", summary: "Ancien", occurred_at: 2.minutes.ago)
        create(:chaster_time_event, user: beta, seconds: 120, source: "cigarettes", summary: "Récent", occurred_at: 1.minute.ago)
        create(:chaster_time_event, seconds: 999, source: "api", occurred_at: Time.current)

        get api_chaster_time_events_path, params: { page: 1, per_page: 1 }, headers: headers
      end

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["events"].size).to eq(1)
      expect(json["events"].first).to include(
        "seconds" => 120,
        "source" => "cigarettes",
        "source_label" => "Cigarettes",
        "summary" => "Récent"
      )
      expect(json["meta"]).to include(
        "page" => 1,
        "per_page" => 1,
        "total_count" => 2,
        "total_pages" => 2,
        "next_page" => 2
      )
    end

    it "returns 401 without auth" do
      get api_chaster_time_events_path

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
