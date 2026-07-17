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
      expect(response.body).to include('data-wallpaper-enforcement-toggle-form="true"')
      expect(response.body).to include('data-wallpaper-enforcement-form="true"')
      expect(response.body).not_to include('actions_hint_html')
      expect(response.body).to include('data-wallpaper-scenarios')
      expect(response.body).to include('data-wallpaper-consequence-composer')
      expect(response.body).to include('data-wallpaper-enforcement-save-bar')
      expect(response.body).to include("requestSubmit()")
      expect(response.body).to include(beta_public_boss_path)
      expect(response.body).to include(beta_catalog_visibility_path)
      expect(response.body).to include(beta_wallpaper_enforcement_path)
    end

    it "shows empty consequence state when no scenarios are configured" do
      config.update!(scenarios: { "scenarios" => [] }, mismatch_sanction: { "items" => [] })

      get beta_sources_wallpaper_path

      expect(response.body).to include('data-wallpaper-scenarios-empty')
      expect(response.body).to include(I18n.t("beta.scenarios.add_consequence"))
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
        dismiss_apps_before_capture: [ "0", "1" ],
        check_interval_minutes: config.check_interval_minutes,
        scenarios: {
          scenarios: {
            "0" => {
              id: "scenario-mismatch-1",
              event: "mismatch",
              trigger: {
                delay_minutes: 30,
                mode: WallpaperEnforcementConfig::SANCTION_MODE_STRICT,
                consecutive_threshold: 3
              },
              actions: {
                "0" => {
                  possibility_id: "chaster.add_time",
                  config: { seconds: 3600 }
                }
              }
            }
          }
        }
      }.deep_merge(overrides)
    end

    it "persists dismiss-apps toggle from checkbox submissions" do
      patch beta_wallpaper_enforcement_path, params: enforcement_params

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      config.reload
      expect(config.dismiss_apps_before_capture).to be true
    end

    it "persists enabled toggle asynchronously via JSON" do
      patch beta_wallpaper_enforcement_path,
        params: { enabled: "1" },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "enabled" => true })
      expect(config.reload.enabled).to be true
    end

    it "disables enforcement asynchronously via JSON" do
      config.update!(enabled: true)

      patch beta_wallpaper_enforcement_path,
        params: { enabled: "0" },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "enabled" => false })
      expect(config.reload.enabled).to be false
    end

    it "persists a consequence into scenarios JSONB" do
      patch beta_wallpaper_enforcement_path, params: enforcement_params

      config.reload
      scenario = config.scenario_for("mismatch")
      expect(scenario).to be_present
      expect(scenario.delay_minutes).to eq(30)
      sanction = scenario.to_sanction_set
      expect(sanction.chaster_add_time_enabled).to be true
      expect(sanction.chaster_seconds).to eq(3600)
    end

    it "persists mismatch trigger mode on the scenario" do
      patch beta_wallpaper_enforcement_path, params: enforcement_params(
        scenarios: {
          scenarios: {
            "0" => {
              id: "scenario-mismatch-1",
              event: "mismatch",
              trigger: {
                delay_minutes: 30,
                mode: WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK,
                consecutive_threshold: 3
              },
              actions: {
                "0" => {
                  possibility_id: "chaster.add_time",
                  config: { seconds: 3600 }
                }
              }
            }
          }
        }
      )

      expect(config.reload.mismatch_sanction_mode).to eq(WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK)
    end
  end
end
