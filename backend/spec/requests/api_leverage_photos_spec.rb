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
    def tlock_upload(content)
      file = Tempfile.new(["layer", ".tlock"])
      file.write(content)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "text/plain", false, original_filename: "layer.tlock")
    end

    it "starts the timer" do
      photo = create(:leverage_photo, :with_images, user: user)
      locked_until = 2.hours.from_now

      post "/api/leverage_photos/#{photo.id}/start",
        params: {
          tlock_blob: tlock_upload("AGE"),
          drand_round: 99_001,
          locked_until: locked_until.iso8601,
          duration_seconds: 7200,
          drand_chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
        },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("active")
      expect(photo.reload.status).to eq("active")
    end
  end
end
