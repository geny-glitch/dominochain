# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperCheckResultNotifier do
  let(:user) { create(:user, :beta, beta_ui_prefs: { "locale" => "fr" }) }
  let(:device) { create(:device, user: user, fcm_token: "fcm-token") }
  let!(:config) do
    create(
      :wallpaper_enforcement_config,
      user: user,
      mismatch_delay_minutes: 30,
      mismatch_sanction: {
        "chaster_add_time_enabled" => true,
        "chaster_seconds" => 600,
        "chaster_freeze_enabled" => false,
        "pishock_enabled" => false,
        "pishock_intensity" => 50,
        "pishock_duration" => 1
      }
    )
  end
  let(:check) do
    user.wallpaper_compliance_checks.create!(
      device: device,
      status: status,
      check_kind: "scheduled",
      similarity_score: similarity_score,
      sanctions_applied: sanctions_applied,
      details: details,
      checked_at: Time.current
    )
  end
  let(:status) { "verified" }
  let(:similarity_score) { 0.92 }
  let(:sanctions_applied) { [] }
  let(:details) { {} }

  before do
    allow(FcmService).to receive(:send_wallpaper_check_result_notification)
  end

  describe ".notify!" do
    it "sends a teasing verified notification" do
      described_class.notify!(check)

      expect(FcmService).to have_received(:send_wallpaper_check_result_notification).with(
        device: device,
        check: check,
        title: "Background check",
        body: "✅"
      )
    end

    it "includes time added when chaster sanction was applied" do
      check.update!(
        status: "mismatch",
        similarity_score: 0.2,
        sanctions_applied: [
          {
            "kind" => "mismatch_add_time",
            "action" => "chaster_add_time",
            "chaster_seconds" => 3661
          }
        ]
      )

      described_class.notify!(check)

      expect(FcmService).to have_received(:send_wallpaper_check_result_notification).with(
        hash_including(
          body: "❌ Vilaine — +1 h 1 min 1 s sur ton lock"
        )
      )
    end

    it "warns before time is added during the grace period" do
      config.update!(mismatch_since: 5.minutes.ago)
      check.update!(status: "mismatch", similarity_score: 0.2)

      described_class.notify!(check)

      expect(FcmService).to have_received(:send_wallpaper_check_result_notification).with(
        hash_including(
          body: a_string_matching(/❌ Vilaine — remets le bon fond avant qu'on ajoute 10 min \(encore 2[45] min/)
        )
      )
    end

    it "uses a simple teasing message for inconclusive checks" do
      check.update!(
        status: "inconclusive",
        similarity_score: nil,
        details: { "inconclusive_reason" => "compare_error" }
      )

      described_class.notify!(check)

      expect(FcmService).to have_received(:send_wallpaper_check_result_notification).with(
        hash_including(body: "🤷 On n'a pas pu vérifier — on réessaie")
      )
    end

    it "skips notification when device has no fcm token" do
      device.update!(fcm_token: nil)

      described_class.notify!(check)

      expect(FcmService).not_to have_received(:send_wallpaper_check_result_notification)
    end
  end
end
