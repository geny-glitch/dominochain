# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperPairReview, type: :model do
  let(:device) { create(:device) }
  let(:wallpaper) { create(:wallpaper, device: device) }
  let(:screenshot) { create(:device_screenshot, device: device, wallpaper: wallpaper) }
  let(:admin) { create(:user, :admin) }

  it "requires a valid expected_status" do
    review = described_class.new(
      device_screenshot: screenshot,
      wallpaper: wallpaper,
      reviewed_by: admin,
      reviewed_at: Time.current,
      expected_status: "invalid"
    )

    expect(review).not_to be_valid
    expect(review.errors[:expected_status]).to be_present
  end

  it "enforces one review per screenshot" do
    described_class.create!(
      device_screenshot: screenshot,
      wallpaper: wallpaper,
      reviewed_by: admin,
      reviewed_at: Time.current,
      expected_status: "verified"
    )

    duplicate = described_class.new(
      device_screenshot: screenshot,
      wallpaper: wallpaper,
      reviewed_by: admin,
      reviewed_at: Time.current,
      expected_status: "mismatch"
    )

    expect(duplicate).not_to be_valid
  end

  describe ".for_regression" do
    it "excludes ignored reviews" do
      ignored_screenshot = create(:device_screenshot, device: device, wallpaper: wallpaper)
      described_class.create!(
        device_screenshot: screenshot,
        wallpaper: wallpaper,
        reviewed_by: admin,
        reviewed_at: Time.current,
        expected_status: "verified"
      )
      described_class.create!(
        device_screenshot: ignored_screenshot,
        wallpaper: wallpaper,
        reviewed_by: admin,
        reviewed_at: Time.current,
        expected_status: "ignored"
      )

      expect(described_class.for_regression.pluck(:device_screenshot_id)).to eq([screenshot.id])
    end
  end
end
