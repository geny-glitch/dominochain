# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::Actions::LeveragePhotoLockFromEvent do
  let(:user) { create(:user, :beta) }

  before do
    stub_beta_catalog_feature_flags("beta_action_leverage_photo" => true)
  end

  it "starts a draft photo via server timer" do
    skip "node is not available" unless system("node", "-v", out: File::NULL, err: File::NULL)

    photo = create(:leverage_photo, :with_images, user: user)
    event = BetaEvents::DomainEvent.new(
      beta: user,
      source: :wallpaper,
      kind: :mismatch_add_time,
      payload: {
        action: "leverage_photo_lock",
        seconds: 3600,
        target_mode: "specific",
        photo_id: photo.id
      }
    )
    context = BetaEvents::Context.new(beta: user, event: event)

    described_class.new.call(context)

    photo.reload
    expect(photo).to be_active
    expect(photo.tlock_blob).to be_attached
    expect(photo.original_image).not_to be_attached
    expect(context.leverage_photo_id).to eq(photo.id)
  end

  it "extends an active photo via add time server" do
    photo = create(:leverage_photo, :active, user: user)
    server = instance_double(LeveragePhotos::AddTimeServer, call!: true)
    allow(LeveragePhotos::AddTimeServer).to receive(:new).and_return(server)

    event = BetaEvents::DomainEvent.new(
      beta: user,
      source: :strava_goal,
      kind: :failed_penalty,
      payload: {
        action: "leverage_photo_lock",
        seconds: 1800,
        target_mode: "specific",
        photo_id: photo.id
      }
    )
    context = BetaEvents::Context.new(beta: user, event: event)

    described_class.new.call(context)

    expect(LeveragePhotos::AddTimeServer).to have_received(:new).with(photo: photo, added_seconds: 1800)
    expect(context.leverage_photo_id).to eq(photo.id)
  end
end
