# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public PiShock page", type: :request do
  let(:beta) do
    create(
      :user,
      :beta,
      nickname: "zapbeta",
      pishock_enabled: true,
      pishock_username: "u",
      pishock_share_code: "c",
      pishock_api_key: "k"
    )
  end

  before do
    beta.update!(
      public_pishock_enabled: true,
      beta_ui_prefs: {
        "catalog_visibility" => {
          "actions" => { "pishock" => true }
        }
      }
    )
    stub_beta_catalog_feature_flags
  end

  describe "GET /zap/:nickname" do
    it "returns not found when public page is disabled" do
      beta.update!(public_pishock_enabled: false)
      get public_pishock_path(beta.nickname)
      expect(response).to have_http_status(:not_found)
    end

    it "shows the control page when enabled" do
      get public_pishock_path(beta.nickname)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="duration"')
      expect(response.body).to include('name="intensity"')
      expect(response.body).to include(public_pishock_shock_path(beta.nickname))
      expect(response.body).to include('id="public-pishock-form"')
      expect(response.body).to include("fetch(form.action")
    end
  end

  describe "POST /zap/:nickname" do
    it "returns an error payload when the shock fails" do
      allow(PishockService).to receive(:shock!).and_return(:auth_error)

      post public_pishock_shock_path(beta.nickname),
           params: { intensity: 40, duration: 2 },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("ok" => false)
      expect(response.parsed_body["error"]).to include("credentials")
    end

    it "sends a notification and success payload when the shock succeeds" do
      device = create(:device, user: beta, fcm_token: "token-1")
      allow(PishockService).to receive(:shock!).and_return(:ok)
      allow(FcmService).to receive(:send_pishock_zap_notification)
      allow(PosthogProductAnalytics).to receive(:pishock_zap)

      post public_pishock_shock_path(beta.nickname),
           params: { intensity: 40, duration: 2 },
           headers: { "Accept" => "application/json" }

      expect(PishockService).to have_received(:shock!).with(user: satisfy { |u| u.id == beta.id }, intensity: 40, duration: 2)
      expect(FcmService).to have_received(:send_pishock_zap_notification).with(
        device: device,
        intensity: 40,
        duration: 2
      )
      expect(PosthogProductAnalytics).to have_received(:pishock_zap).with(
        satisfy { |u| u.id == beta.id },
        intensity: 40,
        duration: 2,
        source: "public_page"
      )
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true, "intensity" => 40, "duration" => 2)
      expect(response.parsed_body["message"]).to be_present
    end

    it "clamps duration to 1..5 and intensity to 0..100" do
      allow(PishockService).to receive(:shock!).and_return(:ok)
      allow(FcmService).to receive(:send_pishock_zap_notification)

      post public_pishock_shock_path(beta.nickname),
           params: { intensity: 999, duration: 99 },
           headers: { "Accept" => "application/json" }

      expect(PishockService).to have_received(:shock!).with(hash_including(intensity: 100, duration: 5))
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /beta/public_pishock" do
    it "enables the public page for the signed-in beta" do
      beta.update!(public_pishock_enabled: false)
      sign_in beta

      patch beta_public_pishock_path, params: { public_pishock_enabled: "1" }

      expect(response).to redirect_to(beta_actions_pishock_path)
      expect(beta.reload.public_pishock_enabled).to be true
    end
  end
end
