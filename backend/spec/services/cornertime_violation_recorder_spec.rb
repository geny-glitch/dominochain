# frozen_string_literal: true

require "rails_helper"

RSpec.describe CornertimeViolationRecorder do
  let(:user) { create(:user, :beta) }
  let(:config) { user.ensure_cornertime_config! }
  let(:session) do
    user.cornertime_sessions.create!(
      status: "active",
      client: "web",
      started_at: Time.current
    )
  end

  before do
    allow_any_instance_of(BetaCatalog).to receive(:source_enabled?).with("cornertime").and_return(true)
    config.update!(
      violation_cooldown_seconds: 30,
      movement_sanction: {
        "items" => [
          {
            "possibility_id" => "chaster.add_time",
            "enabled" => true,
            "config" => { "seconds" => 60 }
          }
        ]
      }
    )
  end

  it "applies sanctions on movement detection" do
    allow(BetaEvents::SanctionApplier).to receive(:new).and_return(
      instance_double(BetaEvents::SanctionApplier, apply!: [{ "possibility_id" => "chaster.add_time", "result" => "ok" }])
    )

    result = described_class.new(session: session, motion_score: 0.12).call

    expect(result.ok).to eq(true)
    expect(result.status).to eq("applied")
    expect(session.reload.violation_count).to eq(1)
    expect(session.cornertime_violations.last.status).to eq("applied")
  end

  it "skips during cooldown window" do
    session.cornertime_violations.create!(
      detected_at: 5.seconds.ago,
      status: "applied",
      actions_executed: []
    )
    session.update!(violation_count: 1)

    result = described_class.new(session: session, motion_score: 0.2).call

    expect(result.ok).to eq(true)
    expect(result.status).to eq("cooldown_skipped")
    expect(result.cooldown_remaining_seconds).to be > 0
    expect(session.reload.violation_count).to eq(1)
  end

  it "returns existing violation for same client_violation_id" do
    existing = session.cornertime_violations.create!(
      detected_at: Time.current,
      status: "applied",
      client_violation_id: "abc-123",
      actions_executed: []
    )

    result = described_class.new(
      session: session,
      client_violation_id: "abc-123",
      motion_score: 0.9
    ).call

    expect(result.violation.id).to eq(existing.id)
    expect(session.cornertime_violations.count).to eq(1)
  end
end
