# frozen_string_literal: true

require "rails_helper"

RSpec.describe PishockShockJob, type: :job do
  it "delegates to PishockService" do
    user = create(:user, pishock_enabled: true, pishock_username: "u", pishock_api_key: "k", pishock_share_code: "c")
    allow(PishockService).to receive(:shock!)

    described_class.perform_now(user.id, 7, 3)

    expect(PishockService).to have_received(:shock!).with(user: user, intensity: 7, duration: 3)
  end

  it "does nothing when user is missing" do
    allow(PishockService).to receive(:shock!)

    described_class.perform_now(0, 1, 1)

    expect(PishockService).not_to have_received(:shock!)
  end
end
