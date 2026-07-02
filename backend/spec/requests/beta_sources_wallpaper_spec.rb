# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Beta sources wallpaper page", type: :request do
  let(:beta) { create(:user, :beta, nickname: "wallpaperbeta", public_boss_enabled: false) }
  let!(:device) { create(:device, user: beta, fcm_token: "token-abc", permissions_ok: true) }
  let!(:config) { create(:wallpaper_enforcement_config, user: beta, enabled: false, dismiss_apps_before_capture: false) }

  before do
    sign_in beta
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true } }
      )
    )
  end

  describe "GET /beta/sources/wallpaper" do
    it "renders toggle forms wired for submit" do
      get beta_sources_wallpaper_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="catalog_source_wallpaper_page"')
      expect(response.body).to include('id="public_boss_enabled"')
      expect(response.body).to include('data-auto-submit="true"')
      expect(response.body).to include('id="wallpaper_enforcement_enabled"')
      expect(response.body).to include('data-wallpaper-enforcement-form="true"')
      expect(response.body).to include('class="ds-radio-group"')
      expect(response.body).to include('name="mismatch_sanction_mode"')
      expect(response.body).to include('type="radio"')
      expect(response.body).to include('data-sanction-row')
      expect(response.body).to include("requestSubmit()")
      expect(response.body).to include(beta_public_boss_path)
      expect(response.body).to include(beta_catalog_visibility_path)
      expect(response.body).to include(beta_wallpaper_enforcement_path)
    end
  end

  describe "catalog source header toggle" do
    it "enables wallpaper source when the checkbox submits hidden 0 and checked 1" do
      patch beta_catalog_visibility_path, params: {
        kind: "source",
        item_id: "wallpaper",
        enabled: [ "0", "1" ],
        return_to: beta_sources_wallpaper_path
      }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.beta_ui_prefs.dig("catalog_visibility", "sources", "wallpaper")).to be true
    end

    it "disables wallpaper source when only hidden 0 is submitted" do
      beta.update!(
        beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
          "catalog_visibility" => { "sources" => { "wallpaper" => true } }
        )
      )

      patch beta_catalog_visibility_path, params: {
        kind: "source",
        item_id: "wallpaper",
        enabled: "0",
        return_to: beta_sources_wallpaper_path
      }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.beta_ui_prefs.dig("catalog_visibility", "sources", "wallpaper")).to be false
    end
  end

  describe "public boss toggle" do
    it "enables public boss mode when the checkbox submits hidden 0 and checked 1" do
      patch beta_public_boss_path, params: { public_boss_enabled: [ "0", "1" ] }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.public_boss_enabled).to be true
    end
  end

  describe "wallpaper enforcement form" do
    def enforcement_params(overrides = {})
      {
        enabled: [ "0", "1" ],
        dismiss_apps_before_capture: [ "0", "1" ],
        check_interval_minutes: config.check_interval_minutes,
        mismatch_delay_minutes: config.mismatch_delay_minutes,
        mismatch_sanction_mode: config.mismatch_sanction_mode,
        mismatch_consecutive_threshold: config.mismatch_consecutive_threshold,
        permissions_lost_delay_minutes: config.permissions_lost_delay_minutes,
        app_unreachable_delay_minutes: config.app_unreachable_delay_minutes,
        app_unreachable_threshold_minutes: config.app_unreachable_threshold_minutes,
        mismatch_sanction: {
          chaster_add_time_enabled: [ "0", "1" ],
          chaster_seconds: 3600,
          chaster_freeze_enabled: "0",
          pishock_enabled: "0",
          pishock_intensity: 50,
          pishock_duration: 1
        },
        permissions_lost_sanction: config.permissions_lost_sanction,
        app_unreachable_sanction: config.app_unreachable_sanction
      }.deep_merge(overrides)
    end

    it "persists enabled and dismiss-apps toggles from checkbox submissions" do
      patch beta_wallpaper_enforcement_path, params: enforcement_params

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      config.reload
      expect(config.enabled).to be true
      expect(config.dismiss_apps_before_capture).to be true
    end

    it "persists sanction toggles from nested checkbox submissions" do
      patch beta_wallpaper_enforcement_path, params: enforcement_params

      sanction = config.reload.mismatch_sanction_object
      expect(sanction.chaster_add_time_enabled).to be true
      expect(sanction.chaster_seconds).to eq(3600)
    end

    it "persists mismatch sanction mode from radio group submission" do
      patch beta_wallpaper_enforcement_path, params: enforcement_params(
        mismatch_sanction_mode: WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK
      )

      expect(config.reload.mismatch_sanction_mode).to eq(WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK)
    end
  end
end
