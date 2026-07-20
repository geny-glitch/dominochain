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
end
