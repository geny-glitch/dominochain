# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotoUnlockJob, type: :job do
  it "unlocks due photos" do
    photo = create(:leverage_photo, :active, locked_until: 1.minute.ago)
    described_class.perform_now
    expect(photo.reload).to be_unlocked
  end

  it "leaves future photos active" do
    photo = create(:leverage_photo, :active, locked_until: 1.day.from_now)
    described_class.perform_now
    expect(photo.reload).to be_active
  end
end
