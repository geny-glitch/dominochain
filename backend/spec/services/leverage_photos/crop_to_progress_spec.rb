# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::CropToProgress do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }
  let(:session) { create(:puzzle_session, user: user, leverage_photo: photo) }

  it "replaces the photo with the progress snapshot and sanctions it" do
    session.progress_snapshot.attach(
      io: StringIO.new("fake-png-bytes"),
      filename: "progress.png",
      content_type: "image/png"
    )

    described_class.call(photo: photo, snapshot: session.progress_snapshot)

    photo.reload
    expect(photo.status).to eq("sanctioned")
    expect(photo.original_image).not_to be_attached
    expect(photo.tlock_blob).not_to be_attached
    expect(photo.censored_image).to be_attached
    expect(photo.teaser_image).to be_attached
  end
end
