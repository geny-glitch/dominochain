# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public boss page (watch/:nickname)", type: :request do
  let(:beta) { create(:user, :beta, nickname: "watchbeta") }
  let!(:device) { create(:device, user: beta) }

  describe "GET /watch/:nickname" do
    it "returns 404 when beta does not exist" do
      get public_boss_path("unknown")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when public boss mode is disabled" do
      beta.update!(public_boss_enabled: false)
      get public_boss_path(beta.nickname)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 200 without authentication when enabled" do
      beta.update!(public_boss_enabled: true)
      get public_boss_path(beta.nickname)
      expect(response).to have_http_status(:ok)
    end

    it "does not require sign-in" do
      beta.update!(public_boss_enabled: true)
      get public_boss_path(beta.nickname)
      expect(response).not_to redirect_to(new_user_session_path)
    end

    it "works when beta has no boss" do
      beta.update!(public_boss_enabled: true)
      expect(beta.control).to be_nil
      get public_boss_path(beta.nickname)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /beta/public_boss" do
    before { sign_in beta }

    it "enables public boss mode" do
      patch beta_public_boss_path, params: { public_boss_enabled: "1" }
      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.public_boss_enabled).to be true
    end

    it "disables public boss mode" do
      beta.update!(public_boss_enabled: true)
      patch beta_public_boss_path, params: { public_boss_enabled: "0" }
      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.public_boss_enabled).to be false
    end
  end
end
