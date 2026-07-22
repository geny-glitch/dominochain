# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chess.com source", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:beta) { create(:user, :beta) }

  before do
    stub_beta_catalog_feature_flags("beta_source_chess" => true)
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "chess" => true } }
      )
    )
    sign_in beta
  end

  describe "account linking" do
    it "starts verification for an existing Chess.com username" do
      service = instance_double(ChessComService)
      allow(ChessComService).to receive(:new).and_return(service)
      allow(service).to receive(:fetch_profile).with("hikaru").and_return(
        { "username" => "hikaru", "player_id" => 15448422 }
      )

      post chess_link_path, params: { username: "Hikaru" }

      expect(response).to redirect_to(beta_sources_chess_path)
      beta.reload
      expect(beta.chess_com_username).to eq("hikaru")
      expect(beta.chess_com_verification_code).to start_with("BG-")
      expect(beta.chess_com_verified_at).to be_nil
      expect(beta.chess_com_verification_pending?).to be true
    end

    it "keeps the same verification code when the username is submitted again while pending" do
      beta.update!(
        chess_com_username: "hikaru",
        chess_com_verification_code: "BG-STABLE",
        chess_com_verification_code_expires_at: 12.hours.from_now,
        chess_com_verified_at: nil
      )
      service = instance_double(ChessComService)
      allow(ChessComService).to receive(:new).and_return(service)
      allow(service).to receive(:fetch_profile).with("hikaru").and_return(
        { "username" => "hikaru", "player_id" => 15448422 }
      )

      post chess_link_path, params: { username: "hikaru" }

      expect(response).to redirect_to(beta_sources_chess_path)
      beta.reload
      expect(beta.chess_com_verification_code).to eq("BG-STABLE")
      expect(beta.chess_com_verification_pending?).to be true
    end

    it "shows the pending verification panel with a verify control" do
      beta.update!(
        chess_com_username: "hikaru",
        chess_com_verification_code: "BG-PANEL1",
        chess_com_verification_code_expires_at: 12.hours.from_now,
        chess_com_verified_at: nil
      )

      get beta_sources_chess_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("BG-PANEL1")
      expect(response.body).to include(I18n.t("beta.chess.verification.verify_button"))
      expect(response.body).to include(I18n.t("beta.chess.verification.status_pending"))
      expect(response.body).not_to include('name="username"')
    end

    it "verifies when the location contains the code" do
      beta.update!(
        chess_com_username: "hikaru",
        chess_com_verification_code: "BG-TEST01",
        chess_com_verification_code_expires_at: 1.hour.from_now
      )
      service = instance_double(ChessComService)
      allow(ChessComService).to receive(:new).and_return(service)
      allow(service).to receive(:verify_location!).with("hikaru", "BG-TEST01").and_return(
        { "username" => "hikaru", "player_id" => 15448422 }
      )

      post chess_verify_path

      expect(response).to redirect_to(beta_sources_chess_path)
      beta.reload
      expect(beta.chess_com_verified?).to be true
      expect(beta.chess_com_player_id).to eq("15448422")
      expect(beta.chess_com_verification_code).to be_nil
      expect(beta.chess_com_verification_pending?).to be false
    end

    it "hides verification setup after the account is verified" do
      beta.update!(
        chess_com_username: "hikaru",
        chess_com_player_id: "15448422",
        chess_com_verified_at: Time.current,
        chess_com_verification_code: nil
      )

      get beta_sources_chess_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("beta.chess.connected_line", username: "hikaru"))
      expect(response.body).not_to include(I18n.t("beta.chess.verification.verify_button"))
      expect(response.body).not_to include(I18n.t("beta.chess.verification.status_pending"))
    end
  end

  describe "goals" do
    before do
      beta.update!(
        chess_com_username: "hikaru",
        chess_com_player_id: "15448422",
        chess_com_verified_at: Time.current
      )
    end

    it "creates a goal with a baseline rating from PubAPI" do
      service = instance_double(ChessComService)
      allow(ChessComService).to receive(:new).and_return(service)
      allow(service).to receive(:current_rating_for!).with("hikaru", "blitz").and_return(1320)

      post beta_chess_goals_path, params: {
        name: "Reach 1400 blitz",
        enabled: "1",
        rating_type: "blitz",
        target_rating: "1400",
        deadline_at: 20.days.from_now.strftime("%Y-%m-%dT%H:%M")
      }

      goal = beta.chess_com_goals.last
      expect(response).to redirect_to(beta_chess_goal_show_path(goal))
      expect(goal.baseline_rating).to eq(1320)
      expect(goal.target_rating).to eq(1400)
      expect(goal.time_zone).to eq(beta.effective_time_zone)
    end

    it "renders the goal page" do
      goal = create(:chess_com_goal, user: beta)

      get beta_chess_goal_show_path(goal)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(goal.name)
    end

    it "runs a preview check before the first interval is due" do
      travel_to Time.zone.parse("2026-07-02 10:15:00") do
        goal = create(
          :chess_com_goal,
          :interval_recurring,
          user: beta,
          target_rating: 1500,
          interval_minutes: 30,
          deadline_at: Time.zone.parse("2026-07-10 20:00:00")
        )
        goal.update_columns(created_at: Time.zone.parse("2026-07-02 10:00:00"), updated_at: Time.zone.parse("2026-07-02 10:00:00"))

        service = instance_double(ChessComService)
        allow(ChessComService).to receive(:new).with(beta).and_return(service)
        allow(service).to receive(:current_rating_for!).with("hikaru", "blitz").and_return(1490)

        expect {
          post beta_chess_goal_preview_check_path(goal)
        }.not_to change { goal.chess_com_goal_checks.count }

        expect(response).to redirect_to(beta_chess_goal_show_path(goal))
        follow_redirect!
        expect(response.body).to include(I18n.t("beta.chess.goal_page.preview_hint"))
      end
    end

    it "runs a manual check before the first interval is due" do
      travel_to Time.zone.parse("2026-07-02 10:15:00") do
        goal = create(
          :chess_com_goal,
          :interval_recurring,
          user: beta,
          target_rating: 1500,
          interval_minutes: 30,
          deadline_at: Time.zone.parse("2026-07-10 20:00:00")
        )
        goal.update_columns(created_at: Time.zone.parse("2026-07-02 10:00:00"), updated_at: Time.zone.parse("2026-07-02 10:00:00"))

        service = instance_double(ChessComService)
        allow(ChessComService).to receive(:new).with(beta).and_return(service)
        allow(service).to receive(:current_rating_for!).with("hikaru", "blitz").and_return(1490)

        expect {
          post beta_chess_goal_check_path(goal)
        }.to change { goal.chess_com_goal_checks.count }.by(1)

        expect(response).to redirect_to(beta_chess_goal_show_path(goal))
        expect(goal.chess_com_goal_checks.last.status).to eq("failed")
      end
    end
  end
end
