# frozen_string_literal: true

require "rails_helper"

RSpec.describe "wallpaper rotation form", type: :request do
  let(:boss) { create(:user, :boss) }
  let(:beta) { create(:user, :beta) }
  let!(:device) { create(:device, user: beta, screen_width: 1080, screen_height: 1920) }

  before do
    create(:control, boss: boss, beta: beta, status: :accepted)
    sign_in boss
    allow(FcmService).to receive(:send_background_changed_notifications)
  end

  def wallpaper_with_image
    wallpaper = create(:wallpaper, device: device)
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: 40,
      height: 80,
      color: [20, 40, 60]
    )
    wallpaper
  end

  it "renders a rotation form when several photos exist" do
    wallpaper_with_image
    wallpaper_with_image

    get wallpaper_upload_path(beta.nickname)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="rotation-enabled"')
    expect(response.body).to include('id="rotation-interval"')
    expect(response.body).to include('id="rotation-collages"')
    expect(response.body).to include(I18n.t("wallpaper.rotation_collages"))
  end

  it "saves the selected photos and the interval" do
    first = wallpaper_with_image
    second = wallpaper_with_image

    post wallpaper_rotation_path(beta.nickname), params: {
      enabled: "1",
      interval: "2",
      interval_unit: "minutes",
      collages: "1",
      wallpaper_ids: [first.id, second.id]
    }

    expect(response).to redirect_to(wallpaper_upload_path(beta.nickname, device_id: device.device_id))
    playlist = device.reload.wallpaper_playlist
    expect(playlist).to be_enabled
    expect(playlist.interval_seconds).to eq(120)
    expect(playlist.collages_enabled).to eq(true)
    expect(playlist.ordered_wallpapers.map(&:id)).to eq([first.id, second.id])
  end
end
