# frozen_string_literal: true

require "rails_helper"

RSpec.describe ZapShockJob, type: :job do
  let(:beta) { create(:user, :beta) }
  let(:program) { create(:zap_program, :armed, beta: beta, generation: 1) }

  before do
    stub_beta_catalog_feature_flags
    enable_pishock_catalog!(beta)
    beta.update!(public_pishock_enabled: true, pishock_intensity_factor: 2)
  end

  it "scales intensity with factor Z and records analytics" do
    allow(PishockService).to receive(:shock!).and_return(:ok)
    allow(PosthogProductAnalytics).to receive(:pishock_zap)

    described_class.perform_now(program.id, 1, 20, 2, "zap_program_public")

    expect(PishockService).to have_received(:shock!).with(user: beta, intensity: 40, duration: 2)
    expect(PosthogProductAnalytics).to have_received(:pishock_zap).with(
      beta,
      intensity: 40,
      duration: 2,
      source: "zap_program_public"
    )
  end

  it "no-ops when generation changed after disarm" do
    allow(PishockService).to receive(:shock!)
    program.disarm!

    described_class.perform_now(program.id, 1, 20, 2, "zap_program_public")

    expect(PishockService).not_to have_received(:shock!)
  end
end
