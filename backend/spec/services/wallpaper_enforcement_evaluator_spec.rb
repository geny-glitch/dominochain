# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperEnforcementEvaluator do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user, last_seen_at: Time.current, permissions_ok: true, fcm_token: "fcm-token") }
  let!(:config) do
    create(
      :wallpaper_enforcement_config,
      user: user,
      enabled: true,
      mismatch_sanction: { "items" => [] },
      scenarios: {
        "scenarios" => [
          {
            "id" => "mismatch-1",
            "event" => "mismatch",
            "trigger" => {
              "delay_minutes" => 30,
              "mode" => WallpaperEnforcementConfig::SANCTION_MODE_STRICT,
              "consecutive_threshold" => 3
            },
            "actions" => [
              {
                "possibility_id" => "chaster.add_time",
                "config" => { "seconds" => 600 }
              }
            ]
          }
        ]
      }
    )
  end
  let(:chaster_service) { instance_double(ChasterService, current_lock: { id: "lock-1", can_freeze: true }) }
  let(:evaluator) { described_class.new(user, chaster_service: chaster_service) }

  def update_mismatch_trigger!(**attrs)
    set = config.scenario_set
    scenario = set.for_event("mismatch")
    trigger = scenario.trigger.merge(attrs)
    updated = ScenarioSet.new(
      scenarios: set.scenarios.map do |s|
        next s unless s.event == "mismatch"

        ScenarioSet::Scenario.new(
          id: s.id,
          event: s.event,
          trigger: trigger,
          actions: s.actions
        )
      end
    )
    config.assign_scenarios!(updated)
    config.save!
  end

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
    it "applies add-time sanction after mismatch delay elapsed" do
      config.update!(mismatch_since: 31.minutes.ago)
      screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

      expect(chaster_service).to receive(:add_time_to_lock).with(
        "lock-1",
        600,
        source: "wallpaper",
        summary: I18n.t("chaster.time_events.summaries.wallpaper.mismatch_add_time"),
        metadata: hash_including("enforcement_kind" => "mismatch_add_time")
      )

      expect do
        evaluator.evaluate_verification!(screenshot: screenshot)
      end.to change { user.wallpaper_compliance_checks.count }.by(1)

      expect(config.reload.add_time_sanction_applied_at).to be_present
      expect(FcmService).to have_received(:send_wallpaper_check_result_notification).with(
        hash_including(device: device, check: an_instance_of(WallpaperComplianceCheck))
      )
    end

    it "applies add-time sanction on every mismatch check after delay elapsed" do
      config.update!(mismatch_since: 2.hours.ago, add_time_sanction_applied_at: 1.hour.ago)
      screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

      expect(chaster_service).to receive(:add_time_to_lock).with(
        "lock-1",
        600,
        source: "wallpaper",
        summary: I18n.t("chaster.time_events.summaries.wallpaper.mismatch_add_time"),
        metadata: hash_including("enforcement_kind" => "mismatch_add_time")
      )

      evaluator.evaluate_verification!(screenshot: screenshot)

      expect(config.reload.add_time_sanction_applied_at).to be > 1.hour.ago
    end

    context "when persisting Chaster history" do
      before do
        allow(ChasterService).to receive(:new).with(user).and_call_original
      end

      it "records a chaster_time_event when add-time sanction is applied" do
        user.update!(chaster_access_token: "token")
        config.update!(mismatch_since: 31.minutes.ago)
        screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

        allow_any_instance_of(ChasterService).to receive(:current_lock).and_return({ id: "lock-1", can_freeze: true })

        success_response = instance_double(Net::HTTPSuccess)
        allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(success_response).to receive(:code).and_return("200")
        allow(Net::HTTP).to receive(:start).and_return(success_response)

        expect {
          evaluator.evaluate_verification!(screenshot: screenshot)
        }.to change { user.chaster_time_events.count }.by(1)

        event = user.chaster_time_events.last
        expect(event.source).to eq("wallpaper")
        expect(event.seconds).to eq(600)
        expect(event.metadata["enforcement_kind"]).to eq("mismatch_add_time")
        expect(event.summary).to eq(I18n.t("chaster.time_events.summaries.wallpaper.mismatch_add_time"))
      end
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

    context "with double_check sanction mode" do
      before do
        update_mismatch_trigger!(mode: WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK)
      end

      it "schedules rechecks instead of applying sanctions while rechecks remain" do
        config.update!(mismatch_since: 31.minutes.ago)
        screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

        expect(chaster_service).not_to receive(:add_time_to_lock)
        expect {
          evaluator.evaluate_verification!(screenshot: screenshot)
        }.to have_enqueued_job(WallpaperMismatchRecheckJob).with(device.id)

        expect(config.reload.mismatch_recheck_count).to eq(1)
      end

      it "applies strict sanctions after rechecks are exhausted" do
        config.update!(
          mismatch_since: 31.minutes.ago,
          mismatch_recheck_count: WallpaperEnforcementConfig::MAX_DOUBLE_CHECK_RECHECKS
        )
        screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

        expect(chaster_service).to receive(:add_time_to_lock).with(
          "lock-1",
          600,
          source: "wallpaper",
          summary: I18n.t("chaster.time_events.summaries.wallpaper.mismatch_add_time"),
          metadata: hash_including("enforcement_kind" => "mismatch_add_time")
        )

        expect {
          evaluator.evaluate_verification!(screenshot: screenshot)
        }.not_to have_enqueued_job(WallpaperMismatchRecheckJob)

        expect(config.reload.add_time_sanction_applied_at).to be_present
      end

      it "resets recheck count when verified" do
        config.update!(mismatch_recheck_count: 2)
        screenshot = create(:device_screenshot, device: device, verification_status: "verified", similarity_score: 0.95)

        evaluator.evaluate_verification!(screenshot: screenshot)

        expect(config.reload.mismatch_recheck_count).to eq(0)
      end
    end

    context "with consecutive_failures sanction mode" do
      before do
        update_mismatch_trigger!(
          mode: WallpaperEnforcementConfig::SANCTION_MODE_CONSECUTIVE_FAILURES,
          consecutive_threshold: 3
        )
      end

      it "does not apply sanctions before the consecutive threshold is reached" do
        screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

        expect(chaster_service).not_to receive(:add_time_to_lock)

        2.times { evaluator.evaluate_verification!(screenshot: screenshot) }

        expect(config.reload.mismatch_consecutive_count).to eq(2)
      end

      it "applies multiplied add-time sanction when the threshold is reached" do
        config.update!(mismatch_consecutive_count: 2)
        screenshot = create(:device_screenshot, device: device, verification_status: "mismatch", similarity_score: 0.2)

        expect(chaster_service).to receive(:add_time_to_lock).with(
          "lock-1",
          1800,
          source: "wallpaper",
          summary: I18n.t("chaster.time_events.summaries.wallpaper.mismatch_add_time"),
          metadata: hash_including("enforcement_kind" => "mismatch_add_time")
        )

        evaluator.evaluate_verification!(screenshot: screenshot)

        expect(config.reload.mismatch_consecutive_count).to eq(0)
      end

      it "resets consecutive count when verified" do
        config.update!(mismatch_consecutive_count: 2)
        screenshot = create(:device_screenshot, device: device, verification_status: "verified", similarity_score: 0.95)

        evaluator.evaluate_verification!(screenshot: screenshot)

        expect(config.reload.mismatch_consecutive_count).to eq(0)
      end
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
