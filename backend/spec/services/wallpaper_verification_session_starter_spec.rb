# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperVerificationSessionStarter do
  let(:beta) { create(:user, :beta) }
  let!(:device) { create(:device, user: beta, fcm_token: "token") }
  let!(:wallpaper) { create(:wallpaper, device: device) }
  let!(:config) { create(:wallpaper_enforcement_config, user: beta, enabled: false) }

  before do
    WallpaperVerificationTestImages.attach_png(wallpaper, attachment_name: :image, width: 100, height: 200, color: [120, 80, 40])
    device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current, applied_by: "beta_self")
    allow(FcmService).to receive(:send_take_screenshot_notification)
  end

  describe "#start!" do
    it "creates an active session and enables enforcement" do
      session = described_class.new(beta).start!(duration_hours: 4)

      expect(session).to be_active
      expect(session.wallpaper).to eq(wallpaper)
      expect(session.config_snapshot["check_interval_minutes"]).to eq(config.check_interval_minutes)
      expect(config.reload.enabled).to be(true)
      expect(FcmService).to have_received(:send_take_screenshot_notification)
    end

    it "raises when a session is already active" do
      create(:wallpaper_verification_session, user: beta, device: device, wallpaper: wallpaper)

      expect {
        described_class.new(beta).start!(duration_hours: 2)
      }.to raise_error(WallpaperVerificationSessionStarter::Error, "active_session")
    end

    it "raises when there is no wallpaper" do
      wallpaper.image.purge

      expect {
        described_class.new(beta).start!(duration_hours: 2)
      }.to raise_error(WallpaperVerificationSessionStarter::Error, "no_wallpaper")
    end
  end
end
