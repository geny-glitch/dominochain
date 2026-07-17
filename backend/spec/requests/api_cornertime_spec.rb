# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Cornertime", type: :request do
  let(:user) { create(:user, :beta) }
  let(:device) { create(:device, user: user) }

  before do
    allow_any_instance_of(BetaCatalog).to receive(:source_enabled?).with("cornertime").and_return(true)
    user.ensure_cornertime_config!.update!(
      violation_cooldown_seconds: 30,
      calibration_seconds: 5,
      sensitivity: "medium",
      movement_sanction: {
        "items" => [
          {
            "possibility_id" => "chaster.add_time",
            "enabled" => true,
            "config" => { "seconds" => 60 }
          }
        ]
      }
    )
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{device.auth_token}",
      "X-Device-Id" => device.device_id
    }
  end

  it "returns config" do
    get "/api/cornertime/config", headers: auth_headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["sensitivity"]).to eq("medium")
    expect(body["motion_threshold"]).to eq(0.12)
    expect(body["detector"]).to eq("diffy_plus_drift")
    expect(body["diff_sensitivity"]).to eq(0.2)
    expect(body["pixel_threshold"]).to eq(21)
    expect(body["drift_threshold"]).to eq(0.18)
    expect(body["drift_hold_ms"]).to eq(1800)
    expect(body["source_enabled"]).to eq(true)
  end

  it "starts and stops a session, then records a violation" do
    allow(BetaEvents::SanctionApplier).to receive(:new).and_return(
      instance_double(BetaEvents::SanctionApplier, apply!: [{ "possibility_id" => "chaster.add_time" }])
    )

    post "/api/cornertime/sessions",
      params: { client: "android" }.to_json,
      headers: auth_headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:created)
    session_id = JSON.parse(response.body).dig("session", "id")

    post "/api/cornertime/sessions/#{session_id}/violations",
      params: {
        motion_score: 0.2,
        client_violation_id: "v-1"
      }.to_json,
      headers: auth_headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["status"]).to eq("applied")

    patch "/api/cornertime/sessions/#{session_id}/stop", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("session", "status")).to eq("stopped")
  end
end
