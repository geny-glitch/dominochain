# frozen_string_literal: true

require "rails_helper"

RSpec.describe Device, "#permissions_granted_for_enforcement?" do
  let(:device) { create(:device) }

  it "returns true when permissions are ok" do
    device.update!(permissions_ok: true, permissions_missing: nil, permissions_checked_at: Time.current)
    expect(device.permissions_granted_for_enforcement?).to eq(true)
  end

  it "returns false when a fresh report says permissions are missing" do
    device.update!(
      permissions_ok: false,
      permissions_missing: '["accessibilité"]',
      permissions_checked_at: 5.minutes.ago
    )
    expect(device.permissions_granted_for_enforcement?).to eq(false)
  end

  it "returns true when a negative report is stale" do
    device.update!(
      permissions_ok: false,
      permissions_missing: '["accessibilité"]',
      permissions_checked_at: 2.hours.ago
    )
    expect(device.permissions_granted_for_enforcement?).to eq(true)
  end
end
