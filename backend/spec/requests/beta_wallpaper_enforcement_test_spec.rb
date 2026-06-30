# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Beta wallpaper enforcement test check", type: :request do
  let(:user) { create(:user, :beta) }
  let!(:device) do
    create(:device, user: user, last_seen_at: Time.current, permissions_ok: true, fcm_token: "token-abc")
  end
  let!(:config) do
    create(:wallpaper_enforcement_config, user: user, enabled: true)
  end

  before do
    sign_in user
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
    user.update!(
      beta_ui_prefs: user.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true } }
      )
    )
    allow(FcmService).to receive(:send_take_screenshot_notification)
  end

  describe "POST /beta/wallpaper/enforcement/test" do
    around do |example|
      previous = ENV["BG_ENV"]
      ENV["BG_ENV"] = "staging"
      example.run
    ensure
      if previous.nil?
        ENV.delete("BG_ENV")
      else
        ENV["BG_ENV"] = previous
      end
    end

    it "runs a scheduled check for the current user" do
      post beta_wallpaper_enforcement_test_path

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(flash[:notice]).to eq(I18n.t("flash.beta.wallpaper.test_triggered"))
      expect(config.reload.last_scheduled_check_at).to be_within(2.seconds).of(Time.current)
      expect(FcmService).to have_received(:send_take_screenshot_notification).with(
        device: device,
        dismiss_apps: config.dismiss_apps_before_capture
      )
    end

    it "rejects the request outside staging" do
      ENV["BG_ENV"] = "production"

      post beta_wallpaper_enforcement_test_path

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(flash[:alert]).to eq(I18n.t("flash.beta.wallpaper.test_staging_only"))
      expect(FcmService).not_to have_received(:send_take_screenshot_notification)
    end
  end
end
