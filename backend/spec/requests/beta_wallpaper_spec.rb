# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaWallpaperController, type: :request do
  let(:user) { create(:user, :beta) }

  before do
    sign_in user
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
  end

  describe "GET /beta/wallpaper/upload" do
    it "allows upload when user has no boss" do
      get beta_wallpaper_upload_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects when user is controlled by a boss" do
      boss = create(:user, :boss)
      create(:control, boss: boss, beta: user, status: :accepted)

      get beta_wallpaper_upload_path
      expect(response).to redirect_to(beta_sources_wallpaper_path)
    end
  end
end
