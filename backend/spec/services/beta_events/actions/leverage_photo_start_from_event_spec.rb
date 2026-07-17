# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::Actions::LeveragePhotoStartFromEvent do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }

  before do
    stub_beta_catalog_feature_flags("beta_action_leverage_photo" => true)
  end

  it "locks a draft photo via server timer" do
    skip "node is not available" unless system("node", "-v", out: File::NULL, err: File::NULL)

    event = BetaEvents::DomainEvent.new(
      beta: user,
      source: :wallpaper,
      kind: :mismatch_add_time,
      payload: {
        action: "leverage_photo_start",
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
end
