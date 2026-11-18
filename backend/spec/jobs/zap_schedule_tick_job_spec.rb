# frozen_string_literal: true

require "rails_helper"

RSpec.describe ZapScheduleTickJob, type: :job do
  include ActiveJob::TestHelper

  let(:beta) { create(:user, :beta, time_zone: "Europe/Paris") }
  let(:program) { create(:zap_program, :armed, beta: beta) }

  before do
    stub_beta_catalog_feature_flags
    enable_pishock_catalog!(beta)
    beta.update!(public_pishock_enabled: true)
  end

  it "enqueues a moment for a due daily slot" do
    create(:zap_slot, zap_program: program, time_of_day_minutes: 8 * 60)
    at = Time.find_zone("Europe/Paris").local(2026, 11, 12, 8, 0, 5)

    expect {
      described_class.perform_now(at.iso8601)
    }.to have_enqueued_job(ZapMomentJob)
  end

  it "skips when the program is busy" do
    create(:zap_slot, zap_program: program, time_of_day_minutes: 8 * 60)
    program.update!(busy_until: 10.minutes.from_now)
    at = Time.find_zone("Europe/Paris").local(2026, 11, 12, 8, 0, 5)

    expect {
      described_class.perform_now(at.iso8601)
    }.not_to have_enqueued_job(ZapMomentJob)
  end

  it "skips disarmed programs" do
    program.disarm!
    create(:zap_slot, zap_program: program, time_of_day_minutes: 8 * 60)
    at = Time.find_zone("Europe/Paris").local(2026, 11, 12, 8, 0, 5)

    expect {
      described_class.perform_now(at.iso8601)
    }.not_to have_enqueued_job(ZapMomentJob)
  end
end
