# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Device screenshots API", type: :request do
  include ActiveJob::TestHelper

  let(:beta) { create(:user, :beta) }
  let(:device) { create(:device, user: beta, screen_width: 540, screen_height: 960) }
  let(:auth_headers) do
    {
      "X-Device-Id" => device.device_id,
      "X-Device-Token" => device.auth_token
    }
  end

  it "creates a screenshot and enqueues wallpaper verification" do
    image = fixture_file_upload(
      Rails.root.join("spec/fixtures/files/wallpaper_reference.png"),
      "image/png"
    )

    expect {
      post "/api/devices/#{device.device_id}/screenshots",
        params: { image: image },
        headers: auth_headers
    }.to have_enqueued_job(WallpaperVerificationJob)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["id"]).to be_present
    expect(body["captured_at"]).to be_present

    screenshot = device.device_screenshots.find(body["id"])
    expect(screenshot.image).to be_attached
    expect(screenshot.verification_status).to eq("pending")
  end

  it "returns 422 when image is missing" do
    post "/api/devices/#{device.device_id}/screenshots", headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
