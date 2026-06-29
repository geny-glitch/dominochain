# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Wallpaper samples API", type: :request do
  include ActiveJob::TestHelper

  let(:beta) { create(:user, :beta) }
  let(:device) { create(:device, user: beta, screen_width: 540, screen_height: 960) }
  let(:auth_headers) do
    {
      "X-Device-Id" => device.device_id,
      "X-Device-Token" => device.auth_token
    }
  end

  it "creates a wallpaper sample and enqueues verification" do
    image = fixture_file_upload(
      Rails.root.join("spec/fixtures/files/wallpaper_reference.png"),
      "image/png"
    )

    expect {
      post "/api/devices/#{device.device_id}/wallpaper_samples",
        params: { image: image },
        headers: auth_headers
    }.to have_enqueued_job(WallpaperVerificationJob)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["id"]).to be_present
    expect(body["sampled_at"]).to be_present

    sample = device.device_wallpaper_samples.find(body["id"])
    expect(sample.image).to be_attached
    expect(sample.verification_status).to eq("pending")
  end

  it "returns 422 when image is missing" do
    post "/api/devices/#{device.device_id}/wallpaper_samples", headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
