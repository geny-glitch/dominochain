# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperEnforcementEvaluator do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user, last_seen_at: Time.current, permissions_ok: true) }
  let!(:config) do
    create(
      :wallpaper_enforcement_config,
      user: user,
      enabled: true,
      mismatch_add_time_delay_minutes: 30,
      mismatch_add_time_sanction: {
        "action" => "chaster_add_time",
        "chaster_seconds" => 600,
        "pishock_intensity" => 50,
        "pishock_duration" => 1
      }
    )
  end
  let(:chaster_service) { instance_double(ChasterService, current_lock: { id: "lock-1" }) }
  let(:evaluator) { described_class.new(user, chaster_service: chaster_service) }

  before do
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true, "beta_action_chaster" => true)
    allow(ChasterService).to receive(:new).with(user).and_return(chaster_service)
    user.update!(
      beta_ui_prefs: user.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true }, "actions" => { "chaster" => true } }
      )
    )
  end

  describe "#evaluate_verification!" do
    it "applies add-time sanction once after mismatch delay elapsed" do
      config.update!(mismatch_since: 31.minutes.ago)
      screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

      expect(chaster_service).to receive(:add_time_to_lock).with(
        "lock-1",
        600,
        source: "wallpaper",
        summary: kind_of(String),
        metadata: kind_of(Hash)
      )

      expect do
        evaluator.evaluate_verification!(screenshot: screenshot)
      end.to change { user.wallpaper_compliance_checks.count }.by(1)

      expect(config.reload.add_time_sanction_applied_at).to be_present
    end

    it "resets mismatch state and unfreezes when verified" do
      config.update!(mismatch_since: 2.hours.ago, frozen_by_enforcement: true)
      screenshot = create(:device_screenshot, device: device, verification_status: "verified", similarity_score: 0.95)

      expect(chaster_service).to receive(:unfreeze_lock).with(
        "lock-1",
        source: "wallpaper",
        summary: kind_of(String),
        metadata: kind_of(Hash)
      )

      evaluator.evaluate_verification!(screenshot: screenshot)

      config.reload
      expect(config.mismatch_since).to be_nil
      expect(config.frozen_by_enforcement).to eq(false)
    end
  end

  describe "#evaluate_scheduled_check!" do
    it "records permissions_missing check when permissions are missing" do
      device.update!(
        permissions_ok: false,
        permissions_missing: '["accessibilité"]',
        permissions_checked_at: Time.current
      )

      expect do
        evaluator.evaluate_scheduled_check!(device: device)
      end.to change { user.wallpaper_compliance_checks.where(status: "permissions_missing").count }.by(1)
    end

    it "ignores stale permissions reports when deciding permissions_missing" do
      device.update!(
        permissions_ok: false,
        permissions_missing: '["accessibilité"]',
        permissions_checked_at: 2.hours.ago
      )

      expect do
        evaluator.evaluate_scheduled_check!(device: device)
      end.not_to change { user.wallpaper_compliance_checks.where(status: "permissions_missing").count }
    end

    it "records app_unreachable when device has not been seen recently" do
      device.update!(last_seen_at: 3.hours.ago)

      expect do
        evaluator.evaluate_scheduled_check!(device: device)
      end.to change { user.wallpaper_compliance_checks.where(status: "app_unreachable").count }.by(1)
    end
  end
end
