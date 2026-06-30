# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperScheduledCheckJob, type: :job do
  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user, last_seen_at: Time.current, permissions_ok: true, fcm_token: "token-abc") }
  let!(:config) do
    create(
      :wallpaper_enforcement_config,
      user: user,
      enabled: true,
      last_scheduled_check_at: 2.hours.ago
    )
  end

  before do
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
    user.update!(
      beta_ui_prefs: user.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true } }
      )
    )
    allow(FcmService).to receive(:send_take_screenshot_notification)
  end

  it "runs scheduled checks for due configs" do
    expect do
      described_class.perform_now
    end.to change { user.wallpaper_compliance_checks.count }.by(0)

    expect(config.reload.last_scheduled_check_at).to be_within(2.seconds).of(Time.current)
    expect(FcmService).to have_received(:send_take_screenshot_notification).with(
      device: device,
      dismiss_apps: true
    )
  end
end
