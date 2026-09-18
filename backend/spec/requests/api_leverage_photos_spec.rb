# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::LeveragePhotos", type: :request do
  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user, fcm_token: "token") }

  before do
    allow_any_instance_of(BetaCatalog).to receive(:action_platform_enabled?).and_call_original
    allow_any_instance_of(BetaCatalog).to receive(:action_platform_enabled?).with("leverage_photo").and_return(true)
    allow_any_instance_of(BetaCatalog).to receive(:source_enabled?).and_call_original
    allow_any_instance_of(BetaCatalog).to receive(:source_enabled?).with("wallpaper").and_return(true)
    allow(FcmService).to receive(:send_background_changed_notifications_to_devices)
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{device.auth_token}",
      "X-Device-Id" => device.device_id
    }
  end

  def image_upload(name = "photo")
    png = ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color.rgb(40, 50, 60))
    file = Tempfile.new([name, ".png"])
    file.binmode
    png.write(file)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "#{name}.png")
  end

  describe "GET /api/leverage_photos" do
    it "lists photos" do
      create(:leverage_photo, :with_images, user: user)

      get "/api/leverage_photos", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["photos"].size).to eq(1)
      expect(body["photos"].first["status"]).to eq("draft")
    end

    it "sorts by unlock date when requested" do
      later = create(:leverage_photo, :active, user: user, locked_until: 3.days.from_now)
      sooner = create(:leverage_photo, :active, user: user, locked_until: 1.hour.from_now)

      get "/api/leverage_photos", params: { sort: "unlock_asc" }, headers: auth_headers

      ids = JSON.parse(response.body)["photos"].map { |row| row["id"] }
      expect(ids).to eq([sooner.id, later.id])
    end
  end

  describe "POST /api/leverage_photos" do
    it "creates a draft photo" do
      post "/api/leverage_photos",
        params: {
          original_image: image_upload,
          teaser_image: image_upload,
          censored_image: image_upload
        },
        headers: auth_headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("draft")
      expect(body["has_original"]).to eq(true)
      expect(body["has_teaser"]).to eq(true)
      expect(body["has_censored"]).to eq(true)
      expect(body["censored_images"].size).to eq(2)
    end
  end

  describe "POST /api/leverage_photos/:id/set_as_wallpaper" do
    it "applies the photo as wallpaper" do
      photo = create(:leverage_photo, :with_images, user: user)

      post "/api/leverage_photos/#{photo.id}/set_as_wallpaper",
        params: { variant: "teaser" }.to_json,
        headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(device.wallpapers.count).to eq(1)
      expect(device.wallpapers.last.leverage_photo_id).to eq(photo.id)
    end
  end

  describe "POST /api/leverage_photos/:id/start" do
    it "starts the timer" do
      photo = create(:leverage_photo, :with_images, user: user)
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
        armored: "AGE-KEY",
        round: 99_001,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )

      post "/api/leverage_photos/#{photo.id}/start",
        params: { duration_seconds: 7200 },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("active")
      expect(photo.reload.status).to eq("active")
      expect(photo.tlock_format).to eq("envelope")
      expect(body.dig("photo", "tlock_format")).to eq("envelope")
    end
  end
end
