# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Wallpaper", type: :request do
  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user, fcm_token: "token", permissions_ok: true) }
  let!(:config) do
    create(
      :wallpaper_enforcement_config,
      user: user,
      enabled: false,
      check_interval_minutes: 60,
      dismiss_apps_before_capture: false
    )
  end

  before do
    allow_any_instance_of(BetaCatalog).to receive(:source_enabled?).and_call_original
    allow_any_instance_of(BetaCatalog).to receive(:source_enabled?).with("wallpaper").and_return(true)
    allow_any_instance_of(BetaCatalog).to receive(:action_platform_enabled?).and_call_original
    allow_any_instance_of(BetaCatalog).to receive(:action_platform_enabled?).with("leverage_photo").and_return(true)
    allow_any_instance_of(BetaCatalog).to receive(:action_enabled?).and_return(true)
    allow(FcmService).to receive(:send_background_changed_notifications)
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{device.auth_token}",
      "X-Device-Id" => device.device_id
    }
  end

  def image_upload
    png = ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color.rgb(10, 20, 30))
    file = Tempfile.new(["wallpaper", ".png"])
    file.binmode
    png.write(file)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "wallpaper.png")
  end

  describe "GET /api/wallpaper/config" do
    it "returns wallpaper config payload" do
      get "/api/wallpaper/config", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["source_enabled"]).to eq(true)
      expect(body["enabled"]).to eq(false)
      expect(body["check_interval_minutes"]).to eq(60)
      expect(body["device"]["connected"]).to eq(true)
      expect(body["verification_session"]["active"]).to eq(false)
      expect(body["locked"]).to eq(false)
      expect(body["allowed_duration_hours"]).to include(1, 24)
    end
  end

  describe "GET /api/wallpaper/scenario_schema" do
    it "returns events and actions" do
      get "/api/wallpaper/scenario_schema", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["events"]).to have_key("mismatch")
      expect(body["actions"]).to be_an(Array)
      expect(body["actions"].map { |a| a["possibility_id"] }).to include("chaster.add_time")
    end
  end

  describe "PATCH /api/wallpaper/config" do
    it "updates enabled and interval" do
      patch "/api/wallpaper/config",
        params: {
          enabled: true,
          check_interval_minutes: 45,
          dismiss_apps_before_capture: true
        }.to_json,
        headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["enabled"]).to eq(true)
      expect(body["check_interval_minutes"]).to eq(45)
      expect(body["dismiss_apps_before_capture"]).to eq(true)
      expect(config.reload.enabled).to eq(true)
    end

    it "replaces scenarios" do
      patch "/api/wallpaper/config",
        params: {
          scenarios: {
            scenarios: [
              {
                event: "mismatch",
                trigger: { delay_minutes: 15, mode: "strict" },
                actions: [
                  { possibility_id: "chaster.add_time", config: { seconds: 600 } }
                ]
              }
            ]
          }
        }.to_json,
        headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:ok)
      scenarios = config.reload.scenario_set.scenarios
      expect(scenarios.size).to eq(1)
      expect(scenarios.first.event).to eq("mismatch")
    end

    it "returns 409 while verification session is active" do
      create(:wallpaper_verification_session, user: user, device: device)

      patch "/api/wallpaper/config",
        params: { enabled: true }.to_json,
        headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /api/wallpaper/upload" do
    it "uploads wallpaper for the user" do
      post "/api/wallpaper/upload",
        params: { image: image_upload },
        headers: auth_headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["id"]).to be_present
      expect(body["url"]).to be_present
      expect(device.wallpapers.count).to eq(1)
      expect(device.wallpaper_applications.last.applied_by).to eq("beta_self")
    end

    it "returns 409 during verification session" do
      create(:wallpaper_verification_session, user: user, device: device)

      post "/api/wallpaper/upload",
        params: { image: image_upload },
        headers: auth_headers

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /api/wallpaper/verification_sessions" do
    def ensure_current_wallpaper!
      wallpaper = create(:wallpaper, device: device)
      WallpaperVerificationTestImages.attach_png(
        wallpaper,
        attachment_name: :image,
        width: 100,
        height: 200,
        color: [90, 90, 90]
      )
      device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current)
      wallpaper
    end

    it "starts a verification session" do
      ensure_current_wallpaper!
      allow_any_instance_of(WallpaperEnforcementEvaluator).to receive(:evaluate_scheduled_check!)

      post "/api/wallpaper/verification_sessions",
        params: { duration_hours: 4 }.to_json,
        headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("session", "active")).to eq(true)
      expect(body.dig("session", "duration_hours")).to eq(4)
      expect(config.reload.enabled).to eq(true)
    end

    it "rejects invalid duration" do
      ensure_current_wallpaper!

      post "/api/wallpaper/verification_sessions",
        params: { duration_hours: 3 }.to_json,
        headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
