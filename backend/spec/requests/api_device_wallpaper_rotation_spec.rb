# frozen_string_literal: true

require "rails_helper"

RSpec.describe "wallpaper rotation api", type: :request do
  let(:user) { create(:user, :beta) }
  let!(:device) { create(:device, user: user, screen_width: 100, screen_height: 200) }

  before do
    allow(FcmService).to receive(:send_background_changed_notifications)
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{device.auth_token}",
      "X-Device-Id" => device.device_id
    }
  end

  def wallpaper_with_image
    wallpaper = create(:wallpaper, device: device)
    wallpaper.image.attach(io: StringIO.new("img"), filename: "a.jpg", content_type: "image/jpeg")
    wallpaper
  end

  it "returns the rotation playlist for the phone" do
    first = wallpaper_with_image
    second = wallpaper_with_image
    WallpaperRotations::Save.new(
      device: device,
      enabled: true,
      interval_seconds: 30,
      collages_enabled: true,
      wallpaper_ids: [first.id, second.id]
    ).call

    get "/api/devices/#{device.device_id}/wallpaper", headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["rotation"]["enabled"]).to eq(true)
    expect(body["rotation"]["interval_seconds"]).to eq(30)
    expect(body["rotation"]["collages"]).to eq(true)
    expect(body["rotation"]["images"].map { |image| image["id"] }).to eq([first.id, second.id])
    expect(body["rotation"]["canvas_width"]).to eq(100)
    expect(body["rotation"]["canvas_height"]).to eq(200)
    expect(body["url"]).to be_present
  end

  it "omits rotation while a verification session is active" do
    first = wallpaper_with_image
    second = wallpaper_with_image
    WallpaperRotations::Save.new(
      device: device,
      enabled: true,
      interval_seconds: 30,
      collages_enabled: true,
      wallpaper_ids: [first.id, second.id]
    ).call
    device.wallpaper_applications.create!(wallpaper: first, applied_at: Time.current, applied_by: "boss")
    create(:wallpaper_verification_session, user: user, device: device, wallpaper: first)

    get "/api/devices/#{device.device_id}/wallpaper", headers: auth_headers

    body = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(body).not_to have_key("rotation")
    expect(body["url"]).to be_present
  end
end
