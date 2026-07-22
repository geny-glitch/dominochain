# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Wallpaper verification sessions", type: :request do
  let(:beta) { create(:user, :beta, nickname: "verifbeta") }
  let!(:device) { create(:device, user: beta, fcm_token: "token", permissions_ok: true) }
  let!(:wallpaper) { create(:wallpaper, device: device) }
  let!(:config) { create(:wallpaper_enforcement_config, user: beta, enabled: true) }

  before do
    WallpaperVerificationTestImages.attach_png(wallpaper, attachment_name: :image, width: 100, height: 200, color: [120, 80, 40])
    device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current, applied_by: "beta_self")
    sign_in beta
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true } }
      )
    )
    allow(FcmService).to receive(:send_take_screenshot_notification)
  end

  describe "POST /beta/wallpaper/verification_sessions" do
    it "starts a verification session" do
      post beta_wallpaper_verification_sessions_path, params: { duration_hours: 4 }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(beta.reload.active_wallpaper_verification_session).to be_present
      follow_redirect!
      expect(response.body).to include(I18n.t("beta.wallpaper_source.verification_session_active_lead"))
    end
  end

  describe "PATCH /beta/wallpaper/enforcement during session" do
    before do
      create(:wallpaper_verification_session, user: beta, device: device, wallpaper: wallpaper)
    end

    it "blocks config updates" do
      patch beta_wallpaper_enforcement_path, params: { check_interval_minutes: 15 }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(config.reload.check_interval_minutes).not_to eq(15)
    end
  end

  describe "POST /beta/wallpaper/upload during session" do
    before do
      create(:wallpaper_verification_session, user: beta, device: device, wallpaper: wallpaper)
    end

    it "blocks wallpaper upload" do
      png = ChunkyPNG::Image.new(100, 200, ChunkyPNG::Color.rgb(10, 20, 30))
      io = StringIO.new
      png.write(io)
      io.rewind

      post beta_wallpaper_create_path,
        params: { image: Rack::Test::UploadedFile.new(io, "image/png", original_filename: "wall.png") }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      expect(device.wallpaper_applications.count).to eq(1)
    end
  end

  describe "GET /beta/wallpaper/upload during session" do
    before do
      create(:wallpaper_verification_session, user: beta, device: device, wallpaper: wallpaper)
    end

    it "redirects away from the upload form" do
      get beta_wallpaper_upload_path

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      follow_redirect!
      expect(flash[:alert]).to eq(I18n.t("flash.beta.wallpaper.verification_session_locked"))
    end
  end

  describe "public boss page during session" do
    before do
      beta.update!(public_boss_enabled: true)
      create(:wallpaper_verification_session, user: beta, device: device, wallpaper: wallpaper)
    end

    it "hides wallpaper change actions and explains the lock" do
      get public_boss_path(beta.nickname)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("wallpaper.verification_session_locked_banner"))
      expect(response.body).not_to include('href="' + public_boss_upload_new_path(beta.nickname, device_id: device.device_id))
      expect(response.body).to include(public_boss_screenshot_request_path(beta.nickname, device_id: device.device_id))
    end

    it "blocks the upload page" do
      get public_boss_upload_new_path(beta.nickname, device_id: device.device_id)

      expect(response).to redirect_to(public_boss_path(beta.nickname, device_id: device.device_id))
      expect(flash[:alert]).to eq(I18n.t("flash.beta.wallpaper.verification_session_locked"))
    end

    it "blocks set_current" do
      previous_wallpaper = create(:wallpaper, device: device)
      WallpaperVerificationTestImages.attach_png(previous_wallpaper, attachment_name: :image, width: 100, height: 200, color: [10, 20, 30])
      device.wallpaper_applications.create!(wallpaper: previous_wallpaper, applied_at: 2.hours.ago)

      post public_boss_set_current_path(beta.nickname, previous_wallpaper.id, device_id: device.device_id)

      expect(response).to redirect_to(public_boss_path(beta.nickname, device_id: device.device_id))
      expect(flash[:alert]).to eq(I18n.t("flash.beta.wallpaper.verification_session_locked"))
      expect(device.wallpaper_applications.recent.first.wallpaper).to eq(wallpaper)
    end
  end
end
