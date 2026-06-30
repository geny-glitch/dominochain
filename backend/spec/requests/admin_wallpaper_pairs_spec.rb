# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin wallpaper pairs", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:device) { create(:device) }
  let(:wallpaper) { create(:wallpaper, device: device) }
  let(:modern_headers) do
    { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0" }
  end

  def attach_labelable_pair(screenshot)
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: 540,
      height: 960,
      color: [120, 80, 200]
    )
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: 540,
      height: 960,
      color: [120, 80, 200]
    )
    perform_enqueued_jobs
    screenshot.update!(wallpaper: wallpaper)
  end

  describe "GET /admin/wallpaper_pairs" do
    it "redirects non-admin users" do
      boss = create(:user, :boss)
      sign_in boss

      get admin_wallpaper_pairs_path, headers: modern_headers

      expect(response).to redirect_to(root_path)
    end

    context "when admin is signed in" do
      before { sign_in admin }

      it "returns 200 and shows unreviewed pairs by default" do
        screenshot = create(:device_screenshot, device: device)
        attach_labelable_pair(screenshot)

        get admin_wallpaper_pairs_path, headers: modern_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Screenshot ##{screenshot.id}")
      end

      it "filters to all pairs when requested" do
        screenshot = create(:device_screenshot, device: device, wallpaper: wallpaper)
        attach_labelable_pair(screenshot)
        WallpaperPairReview.create!(
          device_screenshot: screenshot,
          wallpaper: wallpaper,
          reviewed_by: admin,
          reviewed_at: Time.current,
          expected_status: "verified"
        )

        get admin_wallpaper_pairs_path(filter: "all"), headers: modern_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Screenshot ##{screenshot.id}")
      end

      it "paginates with 30 pairs per page" do
        31.times do
          screenshot = create(:device_screenshot, device: device, wallpaper: wallpaper)
          attach_labelable_pair(screenshot)
        end

        get admin_wallpaper_pairs_path(filter: "all", page: 2), headers: modern_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Page 2")
      end
    end
  end

  describe "POST /admin/wallpaper_pairs/:id/review" do
    let(:screenshot) { create(:device_screenshot, device: device, wallpaper: wallpaper) }

    before do
      attach_labelable_pair(screenshot)
      sign_in admin
    end

    it "creates a review with one click" do
      post admin_wallpaper_pair_review_path(screenshot, expected_status: "verified"),
        headers: modern_headers

      expect(response).to redirect_to(admin_wallpaper_pairs_path)
      review = WallpaperPairReview.find_by!(device_screenshot: screenshot)
      expect(review.expected_status).to eq("verified")
      expect(review.reviewed_by).to eq(admin)
    end

    it "upserts an existing review" do
      WallpaperPairReview.create!(
        device_screenshot: screenshot,
        wallpaper: wallpaper,
        reviewed_by: admin,
        reviewed_at: 1.day.ago,
        expected_status: "verified"
      )

      post admin_wallpaper_pair_review_path(screenshot, expected_status: "mismatch", filter: "all"),
        headers: modern_headers

      expect(WallpaperPairReview.find_by!(device_screenshot: screenshot).expected_status).to eq("mismatch")
    end

    it "rejects invalid status" do
      post admin_wallpaper_pair_review_path(screenshot, expected_status: "bogus"),
        headers: modern_headers

      expect(response).to redirect_to(admin_wallpaper_pairs_path)
      expect(WallpaperPairReview.find_by(device_screenshot: screenshot)).to be_nil
    end
  end
end
