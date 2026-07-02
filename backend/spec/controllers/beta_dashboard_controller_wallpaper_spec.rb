# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaDashboardController, type: :controller do
  render_views
  include Devise::Test::ControllerHelpers

  routes { Rails.application.routes }

  let(:beta) { create(:user, :beta, nickname: "wallpaperbeta", public_boss_enabled: false) }
  let!(:device) { create(:device, user: beta, fcm_token: "token-abc", permissions_ok: true) }
  let!(:config) { create(:wallpaper_enforcement_config, user: beta, enabled: false) }

  before do
    sign_in beta
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true } }
      )
    )
  end

  describe "GET #sources_wallpaper" do
    it "renders interactive toggle markup for catalog, public boss, and enforcement" do
      get :sources_wallpaper

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="catalog_source_wallpaper_page"')
      expect(response.body).to include('id="public_boss_enabled"')
      expect(response.body).to include('data-auto-submit="true"')
      expect(response.body).to include('id="wallpaper_enforcement_enabled"')
      expect(response.body).to include("requestSubmit()")
    end
  end

  describe "PATCH #update_catalog_visibility" do
    it "enables wallpaper source from a checkbox click submission" do
      patch :update_catalog_visibility, params: {
        kind: "source",
        item_id: "wallpaper",
        enabled: [ "0", "1" ],
        return_to: beta_sources_wallpaper_path
      }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.beta_ui_prefs.dig("catalog_visibility", "sources", "wallpaper")).to be true
      expect(PostHog).to have_received(:capture).with(
        distinct_id: beta.posthog_distinct_id,
        event: "activated_source",
        properties: { name: "wallpaper" }
      )
    end
  end

  describe "PATCH #update_public_boss" do
    it "tracks wallpaper source configuration" do
      patch :update_public_boss, params: { public_boss_enabled: [ "0", "1" ] }

      expect(PostHog).to have_received(:capture).with(
        distinct_id: beta.posthog_distinct_id,
        event: "configured_source",
        properties: { name: "wallpaper" }
      )
    end
  end
end
