# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::Actions::LeveragePhotoDeleteFromEvent do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }

  before do
    stub_beta_catalog_feature_flags("beta_action_leverage_photo" => true)
  end

  it "sanctions a photo by deleting the original only" do
    event = BetaEvents::DomainEvent.new(
      beta: user,
      source: :wallpaper,
      kind: :mismatch_add_time,
      payload: {
        action: "leverage_photo_delete",
        target_mode: "specific",
        photo_id: photo.id
      }
    )
    context = BetaEvents::Context.new(beta: user, event: event)

    described_class.new.call(context)

    photo.reload
    expect(photo).to be_sanctioned
    expect(photo.original_image).not_to be_attached
    expect(photo.censored_image).to be_attached
    expect(photo.teaser_image).to be_attached
    expect(context.leverage_photo_id).to eq(photo.id)
  end

  it "stops when no eligible photo exists" do
    BetaEvents::ActionExecutor # ensure ActionExecutionStopped is loaded

    event = BetaEvents::DomainEvent.new(
      beta: user,
      source: :wallpaper,
      kind: :mismatch_add_time,
      payload: {
        action: "leverage_photo_delete",
        target_mode: "random"
      }
    )
    context = BetaEvents::Context.new(beta: user, event: event)

    expect {
      described_class.new.call(context)
    }.to raise_error(BetaEvents::ActionExecutionStopped) { |error|
      expect(error.reason).to eq(:no_eligible_photo)
    }
  end
end
