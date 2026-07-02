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
        expect(response.body).to include("ds-wallpaper-pairs-table")
        expect(response.body).to include("Run")
        expect(response.body).to include('name="algorithm"')
      end

      it "filters disagreements when requested" do
        reviewed_screenshot = create(:device_screenshot, device: device, wallpaper: wallpaper)
        attach_labelable_pair(reviewed_screenshot)
        WallpaperPairReview.create!(
          device_screenshot: reviewed_screenshot,
          wallpaper: wallpaper,
          reviewed_by: admin,
          reviewed_at: Time.current,
          expected_status: "verified"
        )
        WallpaperAlgorithmComparison.create!(
          device_screenshot: reviewed_screenshot,
          algorithm: "local_match",
          status: "mismatch",
          score: 0.2,
          compared_at: Time.current
        )

        agreeing_screenshot = create(:device_screenshot, device: device, wallpaper: wallpaper)
        attach_labelable_pair(agreeing_screenshot)
        WallpaperPairReview.create!(
          device_screenshot: agreeing_screenshot,
          wallpaper: wallpaper,
          reviewed_by: admin,
          reviewed_at: Time.current,
          expected_status: "verified"
        )
        WallpaperAlgorithmComparison.create!(
          device_screenshot: agreeing_screenshot,
          algorithm: "local_match",
          status: "verified",
          score: 0.9,
          compared_at: Time.current
        )

        get admin_wallpaper_pairs_path(filter: "disagreements"), headers: modern_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Screenshot ##{reviewed_screenshot.id}")
        expect(response.body).not_to include("Screenshot ##{agreeing_screenshot.id}")
        expect(response.body).to include("ds-wallpaper-pairs-table__row--disagreement")
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

  describe "POST /admin/wallpaper_pairs/:id/run_algorithm" do
    let(:screenshot) { create(:device_screenshot, device: device, wallpaper: wallpaper) }

    before do
      attach_labelable_pair(screenshot)
      sign_in admin
    end

    it "runs the requested algorithm and stores the result" do
      post admin_wallpaper_pair_run_algorithm_path(screenshot),
        params: { algorithm: "local_match" },
        headers: modern_headers

      expect(response).to redirect_to(admin_wallpaper_pairs_path)
      comparison = WallpaperAlgorithmComparison.find_by!(device_screenshot: screenshot, algorithm: "local_match")
      expect(comparison.status).to eq("verified")
      expect(comparison.score).to be >= 0.85
    end

    it "shows stored algorithm results on the pairs page" do
      WallpaperAlgorithmComparison.create!(
        device_screenshot: screenshot,
        algorithm: "grid_fuzzy",
        status: "verified",
        score: 0.91,
        compared_at: Time.current
      )

      get admin_wallpaper_pairs_path(filter: "all"), headers: modern_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grid fuzzy")
      expect(response.body).to include("verified · 91%")
    end

    it "rejects unknown algorithms" do
      post admin_wallpaper_pair_run_algorithm_path(screenshot),
        params: { algorithm: "unknown" },
        headers: modern_headers

      expect(response).to redirect_to(admin_wallpaper_pairs_path)
      expect(WallpaperAlgorithmComparison.count).to eq(0)
    end
  end

  describe "POST /admin/wallpaper_pairs/export_disagreements" do
    let(:screenshot) { create(:device_screenshot, device: device, wallpaper: wallpaper) }
    let(:export_root) { Rails.root.join("tmp/wallpaper_pairs_request_spec") }

    before do
      attach_labelable_pair(screenshot)
      sign_in admin
      allow(WallpaperPairsDatasetExporter).to receive(:new).and_return(
        WallpaperPairsDatasetExporter.new(root: export_root)
      )
      FileUtils.rm_rf(export_root)
    end

    after do
      FileUtils.rm_rf(export_root)
    end

    it "exports disagreements to wallpaper_pairs/" do
      WallpaperPairReview.create!(
        device_screenshot: screenshot,
        wallpaper: wallpaper,
        reviewed_by: admin,
        reviewed_at: Time.current,
        expected_status: "mismatch"
      )
      WallpaperAlgorithmComparison.create!(
        device_screenshot: screenshot,
        algorithm: "local_match",
        status: "verified",
        score: 0.91,
        compared_at: Time.current
      )

      post admin_wallpaper_pairs_export_disagreements_path, headers: modern_headers

      expect(response).to redirect_to(admin_wallpaper_pairs_path(filter: "disagreements"))
      expect(File).to exist(export_root.join("mismatch", "screenshot_#{screenshot.id}", "manifest.json"))
    end
  end
end
