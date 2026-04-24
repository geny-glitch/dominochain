# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PiShock debug page", type: :request do
  describe "GET /beta/pishock/debug" do
    it "redirects when not signed in" do
      get beta_pishock_debug_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns 200 for beta" do
      sign_in create(:user, :beta)
      get beta_pishock_debug_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects boss away from beta-only debug" do
      sign_in create(:user, :boss)
      get beta_pishock_debug_path
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to match(/betas/i)
    end
  end

  describe "POST /beta/pishock/debug/step1" do
    let(:beta) { create(:user, :beta) }

    before { sign_in beta }

    it "redirects with alert when fields are blank" do
      post beta_pishock_debug_step1_path, params: { pishock_debug: { username: "", apikey: "" } }
      expect(response).to redirect_to(beta_pishock_debug_path)
      expect(flash[:alert]).to be_present
    end

    it "calls auth endpoint and stores UserId in session" do
      allow_any_instance_of(PishockDebugController).to receive(:http_get).and_return(
        http_status: 200,
        http_success: true,
        body: '{"UserId":99,"Username":"u"}'
      )

      post beta_pishock_debug_step1_path, params: { pishock_debug: { username: "u", apikey: "k" } }
      expect(response).to redirect_to(beta_pishock_debug_path)

      get beta_pishock_debug_path
      expect(response.body).to include("99")
    end
  end
end
