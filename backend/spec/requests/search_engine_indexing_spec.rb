# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Search engine indexing", type: :request do
  describe "GET /robots.txt" do
    it "blocks all crawlers outside production" do
      get "/robots.txt"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to include("Disallow: /")
      expect(response.body).not_to include("Allow:")
    end

    it "allows only the homepage in production" do
      allow(SearchEngineIndexing).to receive(:production?).and_return(true)

      get "/robots.txt"

      expect(response.body).to include("Disallow: /")
      expect(response.body).to include("Allow: /$")
    end
  end

  describe "HTML responses" do
    it "marks non-homepage pages as noindex" do
      get new_user_session_path

      expect(response.body).to include('<meta name="robots" content="noindex, nofollow, noarchive, nosnippet">')
      expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow, noarchive, nosnippet")
    end

    it "does not mark the homepage as noindex in production" do
      allow(SearchEngineIndexing).to receive(:production?).and_return(true)

      get root_path

      expect(response.body).not_to include('<meta name="robots" content="noindex')
      expect(response.headers["X-Robots-Tag"]).to be_nil
    end

    it "marks the homepage as noindex outside production" do
      get root_path

      expect(response.body).to include('<meta name="robots" content="noindex, nofollow, noarchive, nosnippet">')
      expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow, noarchive, nosnippet")
    end
  end
end
