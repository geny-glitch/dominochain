# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowcaseGameStartedNotifyJob, type: :job do
  it "sends a start notification to each device" do
    user = create(:user, :beta)
    first_device = create(:device, user: user)
    second_device = create(:device, user: user)

    described_class.perform_now(user.id, 123, "snake", "Alice")

    expect(FcmService).to have_received(:send_showcase_game_started_notification).with(
      device: first_device,
      game_session_id: 123,
      game_type: "snake",
      player_name: "Alice"
    )
    expect(FcmService).to have_received(:send_showcase_game_started_notification).with(
      device: second_device,
      game_session_id: 123,
      game_type: "snake",
      player_name: "Alice"
    )
  end

  it "does nothing when user is missing" do
    described_class.perform_now(0, 123, "snake")

    expect(FcmService).not_to have_received(:send_showcase_game_started_notification)
  end
end
