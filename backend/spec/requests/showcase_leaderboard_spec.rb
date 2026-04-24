# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Showcase leaderboard", type: :request do
  let(:beta) { create(:user, :beta, nickname: "lbtest") }

  describe "GET /showcase/:nickname/leaderboard" do
    it "returns paginated entries with metadata" do
      create(:game_session, user: beta, game_type: "quiz", player_name: "A", score: 10, played_at: 2.days.ago)
      create(:game_session, user: beta, game_type: "quiz", player_name: "B", score: 99, played_at: 1.day.ago)

      get showcase_leaderboard_path(beta.nickname), params: { game_type: "quiz", sort: "score", page: 1, per_page: 10 }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["total"]).to eq(2)
      expect(json["entries"].length).to eq(2)
      expect(json["entries"].first["rank"]).to eq(1)
      expect(json["entries"].first["player_name"]).to eq("B")
      expect(json["entries"].first).to include("played_at", "score")
    end

    it "orders by most recent when sort=recent" do
      create(:game_session, user: beta, game_type: "snake", player_name: "Old", score: 100, played_at: 3.days.ago)
      create(:game_session, user: beta, game_type: "snake", player_name: "New", score: 1, played_at: Time.current)

      get showcase_leaderboard_path(beta.nickname), params: { game_type: "snake", sort: "recent", page: 1, per_page: 10 }

      json = response.parsed_body
      expect(json["sort"]).to eq("recent")
      expect(json["entries"].first["player_name"]).to eq("New")
    end

    it "returns 404 for unknown beta" do
      get showcase_leaderboard_path("nonexistent_nick")
      expect(response).to have_http_status(:not_found)
    end
  end
end
