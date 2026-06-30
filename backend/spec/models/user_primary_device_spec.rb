# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "#primary_device" do
  let(:user) { create(:user, :beta) }

  it "prefers a recently seen device over a device with no last_seen_at" do
    ghost = create(:device, user: user, device_id: "ghost-device", last_seen_at: nil, fcm_token: nil)
    active = create(
      :device,
      user: user,
      device_id: "active-device",
      last_seen_at: 2.minutes.ago,
      fcm_token: "token-active"
    )

    expect(user.primary_device).to eq(active)
    expect(user.primary_device).not_to eq(ghost)
  end
end
