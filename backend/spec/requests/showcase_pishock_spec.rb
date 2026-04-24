# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Showcase PiShock hooks", type: :request do
  include ActiveJob::TestHelper

  let(:beta) do
    create(:user, :beta, nickname: "pibeta", pishock_enabled: true,
      pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k")
  end

  describe "POST /showcase/:nickname/add_time" do
    it "enqueues PishockShockJob for snake" do
      expect do
        post showcase_add_time_path(beta.nickname), params: { game_type: "snake" }
      end.to have_enqueued_job(PishockShockJob).with(beta.id, 1, 1)
    end
  end

  describe "PATCH /showcase/:nickname/sessions/:id" do
    let(:game_session) { create(:game_session, user: beta, player_name: nil, score: 42) }

    it "enqueues PishockShockJob with score capped on first player_name" do
      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.to have_enqueued_job(PishockShockJob).with(beta.id, 42, 1)
    end

    it "uses intensity min(score, 100)" do
      game_session.update!(score: 150)
      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.to have_enqueued_job(PishockShockJob).with(beta.id, 100, 1)
    end

    it "does not enqueue when player_name was already set" do
      game_session.update!(player_name: "Bob")
      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job(PishockShockJob)
    end
  end
end
