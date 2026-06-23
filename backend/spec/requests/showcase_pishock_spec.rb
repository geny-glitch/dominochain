# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Showcase PiShock hooks", type: :request do
  include ActiveJob::TestHelper

  let(:beta) do
    create(:user, :beta, nickname: "pibeta", pishock_enabled: true,
      pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k")
  end
  let(:feature_flag_overrides) { {} }
  let(:feature_flag_evaluations) do
    Struct.new(:overrides) do
      def enabled?(key)
        overrides.fetch(key.to_s, true)
      end
    end.new(feature_flag_overrides)
  end

  before do
    beta.update!(
      showcase_snake_enabled: true,
      showcase_tetris_enabled: true,
      beta_ui_prefs: {
        "catalog_visibility" => {
          "sources" => { "showcase" => true },
          "actions" => { "chaster" => true, "pishock" => true }
        }
      }
    )
    stub_beta_catalog_feature_flags(feature_flag_overrides)
  end

  describe "POST /showcase/:nickname/add_time" do
    it "enqueues PishockShockJob for snake" do
      expect do
        post showcase_add_time_path(beta.nickname), params: { game_type: "snake" }
      end.to have_enqueued_job(PishockShockJob).with(beta.id, 1, 1)
    end

    it "does not enqueue PishockShockJob for dino minute scoring" do
      service_double = instance_double(ChasterService, current_lock: { id: "lock-1" })
      allow(service_double).to receive(:add_time_to_lock)
      allow(ChasterService).to receive(:new).with(beta).and_return(service_double)

      expect do
        post showcase_add_time_path(beta.nickname), params: { game_type: "dino" }
      end.not_to have_enqueued_job(PishockShockJob)
    end

    it "does not enqueue PishockShockJob when PiShock is disabled by the user" do
      beta.update!(pishock_enabled: false)

      expect do
        post showcase_add_time_path(beta.nickname), params: { game_type: "snake" }
      end.not_to have_enqueued_job(PishockShockJob)
    end

    context "when pishock action feature flag is disabled" do
      let(:feature_flag_overrides) { { "beta_action_pishock" => false } }

      it "does not enqueue PishockShockJob" do
        expect do
          post showcase_add_time_path(beta.nickname), params: { game_type: "snake" }
        end.not_to have_enqueued_job(PishockShockJob)
      end
    end

    context "tetris line clears" do
      let(:beta) do
        create(:user, :beta, nickname: "pibeta",
          pishock_enabled: true,
          pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k",
          showcase_tetris_enabled: true)
      end

      it "enqueues PishockShockJob with intensity and duration equal to lines count (Z=1)" do
        service_double = instance_double(ChasterService, current_lock: { id: "lock-1" })
        allow(service_double).to receive(:add_time_to_lock)
        allow(ChasterService).to receive(:new).with(beta).and_return(service_double)

        expect do
          post showcase_add_time_path(beta.nickname), params: { game_type: "tetris", lines: "3" }
        end.to have_enqueued_job(PishockShockJob).with(beta.id, 3, 3)
      end

      it "enqueues PishockShockJob with lines=8 for Tetris (4 lignes doublées)" do
        service_double = instance_double(ChasterService, current_lock: { id: "lock-1" })
        allow(service_double).to receive(:add_time_to_lock)
        allow(ChasterService).to receive(:new).with(beta).and_return(service_double)

        expect do
          post showcase_add_time_path(beta.nickname), params: { game_type: "tetris", lines: "8" }
        end.to have_enqueued_job(PishockShockJob).with(beta.id, 8, 8)
      end

      it "clamps lines to 8 max" do
        service_double = instance_double(ChasterService, current_lock: { id: "lock-1" })
        allow(service_double).to receive(:add_time_to_lock)
        allow(ChasterService).to receive(:new).with(beta).and_return(service_double)

        expect do
          post showcase_add_time_path(beta.nickname), params: { game_type: "tetris", lines: "99" }
        end.to have_enqueued_job(PishockShockJob).with(beta.id, 8, 8)
      end

      context "avec facteur Z=10" do
        let(:beta) do
          create(:user, :beta, nickname: "pibeta",
            pishock_enabled: true,
            pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k",
            showcase_tetris_enabled: true,
            pishock_intensity_factor: 10)
        end

        it "multiplie l'intensité par Z, durée inchangée" do
          service_double = instance_double(ChasterService, current_lock: { id: "lock-1" })
          allow(service_double).to receive(:add_time_to_lock)
          allow(ChasterService).to receive(:new).with(beta).and_return(service_double)

          expect do
            post showcase_add_time_path(beta.nickname), params: { game_type: "tetris", lines: "3" }
          end.to have_enqueued_job(PishockShockJob).with(beta.id, 30, 3)
        end

        it "plafonne l'intensité à 100 même avec Z élevé" do
          service_double = instance_double(ChasterService, current_lock: { id: "lock-1" })
          allow(service_double).to receive(:add_time_to_lock)
          allow(ChasterService).to receive(:new).with(beta).and_return(service_double)

          expect do
            post showcase_add_time_path(beta.nickname), params: { game_type: "tetris", lines: "8" }
          end.to have_enqueued_job(PishockShockJob).with(beta.id, 80, 8)
        end
      end
    end

    context "snake avec facteur Z=5" do
      let(:beta) do
        create(:user, :beta, nickname: "pibeta",
          pishock_enabled: true,
          pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k",
          pishock_intensity_factor: 5)
      end

      it "multiplie l'intensité snake par Z" do
        expect do
          post showcase_add_time_path(beta.nickname), params: { game_type: "snake" }
        end.to have_enqueued_job(PishockShockJob).with(beta.id, 5, 1)
      end
    end
  end

  describe "POST /showcase/:nickname/sessions" do
    it "enqueues a game-start notification when a game begins" do
      expect do
        post showcase_create_session_path(beta.nickname),
          params: { game_type: "snake" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.to have_enqueued_job(ShowcaseGameStartedNotifyJob).with(beta.id, kind_of(Integer), "snake")
    end

    it "passes the showcase player cookie to the game-start notification" do
      beta.update!(nickname: "pi_beta")
      cookies["bgShowcasePlayer_pi_beta"] = "  Alice  "

      expect do
        post showcase_create_session_path(beta.nickname),
          params: { game_type: "snake" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.to have_enqueued_job(ShowcaseGameStartedNotifyJob).with(beta.id, kind_of(Integer), "snake", "Alice")
    end

    it "does not enqueue a game-start notification when the game is disabled" do
      beta.update!(showcase_snake_enabled: false)

      expect do
        post showcase_create_session_path(beta.nickname),
          params: { game_type: "snake" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job(ShowcaseGameStartedNotifyJob)
    end
  end

  describe "PATCH /showcase/:nickname/sessions/:id" do
    let(:game_session) { create(:game_session, user: beta, player_name: nil, score: 42) }

    it "enqueues PishockShockJob with score capped on first player_name (non-tetris, duration=1)" do
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

    it "does not enqueue PiShock or notify when player_name was already set" do
      game_session.update!(player_name: "Bob")
      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job
    end

    it "enqueues ShowcaseBetaNotifyJob when player_name is submitted" do
      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.to have_enqueued_job(ShowcaseBetaNotifyJob).with(beta.id, "Alice", 42, "snake")
    end

    it "does not enqueue PiShock when pishock action is disabled in catalog" do
      beta.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "pishock" => false } } })

      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job(PishockShockJob)
    end

    it "does not enqueue PiShock when showcase source is disabled in catalog" do
      beta.update!(beta_ui_prefs: { "catalog_visibility" => { "sources" => { "showcase" => false } } })

      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job(PishockShockJob)
    end

    it "does not enqueue PiShock when PiShock is disabled by the user" do
      beta.update!(pishock_enabled: false)

      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { player_name: "Alice" },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job(PishockShockJob)
    end

    context "when feature flags disable PiShock action or Showcase source" do
      context "with pishock action feature flag disabled" do
        let(:feature_flag_overrides) { { "beta_action_pishock" => false } }

        it "does not enqueue PiShock" do
          expect do
            patch showcase_update_session_path(beta.nickname, game_session.id),
              params: { player_name: "Alice" },
              headers: { "Content-Type" => "application/json" },
              as: :json
          end.not_to have_enqueued_job(PishockShockJob)
        end
      end

      context "with showcase source feature flag disabled" do
        let(:feature_flag_overrides) { { "beta_source_showcase" => false } }

        it "does not enqueue PiShock" do
          expect do
            patch showcase_update_session_path(beta.nickname, game_session.id),
              params: { player_name: "Alice" },
              headers: { "Content-Type" => "application/json" },
              as: :json
          end.not_to have_enqueued_job(PishockShockJob)
        end
      end
    end

    it "does not enqueue showcase notify when only score is patched" do
      expect do
        patch showcase_update_session_path(beta.nickname, game_session.id),
          params: { score: 10 },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.not_to have_enqueued_job(ShowcaseBetaNotifyJob)
    end

    context "tetris end-of-game" do
      let(:beta) do
        create(:user, :beta, nickname: "pibeta",
          pishock_enabled: true,
          pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k",
          showcase_tetris_enabled: true)
      end
      let(:tetris_session) { create(:game_session, user: beta, game_type: "tetris", player_name: nil, score: 10) }

      it "enqueues PishockShockJob with intensity=score and duration=score (Z=1)" do
        expect do
          patch showcase_update_session_path(beta.nickname, tetris_session.id),
            params: { player_name: "Alice" },
            headers: { "Content-Type" => "application/json" },
            as: :json
        end.to have_enqueued_job(PishockShockJob).with(beta.id, 10, 10)
      end

      it "caps intensity at 100 and duration at 15 for high scores" do
        tetris_session.update!(score: 200)
        expect do
          patch showcase_update_session_path(beta.nickname, tetris_session.id),
            params: { player_name: "Alice" },
            headers: { "Content-Type" => "application/json" },
            as: :json
        end.to have_enqueued_job(PishockShockJob).with(beta.id, 100, 15)
      end

      context "avec facteur Z=3" do
        let(:beta) do
          create(:user, :beta, nickname: "pibeta",
            pishock_enabled: true,
            pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k",
            showcase_tetris_enabled: true,
            pishock_intensity_factor: 3)
        end

        it "multiplie l'intensité fin de partie par Z, durée basée sur score brut" do
          expect do
            patch showcase_update_session_path(beta.nickname, tetris_session.id),
              params: { player_name: "Alice" },
              headers: { "Content-Type" => "application/json" },
              as: :json
          end.to have_enqueued_job(PishockShockJob).with(beta.id, 30, 10)
        end
      end
    end
  end
end
