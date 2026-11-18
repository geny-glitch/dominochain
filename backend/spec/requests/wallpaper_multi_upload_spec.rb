# frozen_string_literal: true

require "rails_helper"

RSpec.describe "wallpaper multi upload", type: :request do
  before do
    allow(FcmService).to receive(:send_background_changed_notifications)
  end

  def png_upload(red, green, blue)
    png = ChunkyPNG::Image.new(16, 32, ChunkyPNG::Color.rgb(red, green, blue))
    file = Tempfile.new(["wallpaper", ".png"])
    file.binmode
    png.write(file.path)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  describe "boss chooser" do
    let(:boss) { create(:user, :boss) }
    let(:beta) { create(:user, :beta) }
    let!(:device) { create(:device, user: beta, screen_width: 1080, screen_height: 1920) }

    before do
      create(:control, boss: boss, beta: beta, status: :accepted)
      sign_in boss
    end

    it "lets the file picker accept several photos" do
      get wallpaper_upload_new_path(beta.nickname)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("multiple")
      expect(response.body).to include(I18n.t("wallpaper.upload.choose_images"))
      expect(response.body).to include(I18n.t("wallpaper.upload.choose_help"))
    end

    it "saves several photos so they take turns" do
      post wallpaper_upload_submit_path(beta.nickname), params: {
        images: [png_upload(10, 20, 30), png_upload(200, 10, 10)]
      }

      expect(response).to redirect_to(wallpaper_upload_path(beta.nickname, device_id: device.device_id))
      playlist = device.reload.wallpaper_playlist
      expect(playlist).to be_enabled
      expect(playlist.ordered_wallpapers.size).to eq(2)
      expect(flash[:notice]).to eq(I18n.t("flash.wallpaper.uploaded_many"))
    end
  end

  describe "beta chooser" do
    let(:user) { create(:user, :beta) }
    let!(:device) { create(:device, user: user) }

    before do
      sign_in user
      stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
    end

    it "lets the file field accept several photos" do
      get beta_wallpaper_upload_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="wallpaper-images"')
      expect(response.body).to include("multiple")
    end

    it "saves several photos so they take turns" do
      post beta_wallpaper_create_path, params: {
        images: [png_upload(10, 20, 30), png_upload(200, 10, 10)]
      }

      expect(response).to redirect_to(beta_sources_wallpaper_path)
      playlist = device.reload.wallpaper_playlist
      expect(playlist).to be_enabled
      expect(playlist.ordered_wallpapers.size).to eq(2)
    end
  end
end
