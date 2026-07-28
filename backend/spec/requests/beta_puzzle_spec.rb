# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Beta puzzle", type: :request do
  let(:beta) { create(:user, :beta) }
  let!(:photo) { create(:leverage_photo, :with_images, user: beta) }

  before do
    stub_beta_catalog_feature_flags(
      "beta_source_puzzle" => true,
      "beta_action_puzzle" => true,
      "beta_action_leverage_photo" => true
    )
    sign_in beta
  end

  it "renders the puzzle source page" do
    get beta_sources_puzzle_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Puzzle")
  end

  it "creates and starts a puzzle session" do
    post beta_puzzles_create_path, params: {
      image_source: "leverage_photo",
      leverage_photo_id: photo.id,
      piece_count: 9,
      reference_mode: "blurred"
    }
    session = beta.puzzle_sessions.last
    expect(response).to redirect_to(beta_puzzle_path(session))

    post beta_puzzle_start_path(session), as: :json
    expect(response).to have_http_status(:ok)
    expect(session.reload.status).to eq("active")
    expect(session.deadline_at).to be_nil
  end

  it "finishes a completed puzzle" do
    session = create(
      :puzzle_session,
      :active,
      user: beta,
      leverage_photo: photo,
      piece_count: 9,
      grid_cols: 3,
      grid_rows: 3,
      pieces_total: 9
    )

    post beta_puzzle_finish_path(session), params: {
      outcome: "complete",
      pieces_placed: 9,
      piece_positions: (0...9).to_a
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(session.reload.status).to eq("completed")
  end

  it "abandons an active puzzle" do
    session = create(:puzzle_session, :active, user: beta, leverage_photo: photo)

    post beta_puzzle_finish_path(session), params: { outcome: "abandon", pieces_placed: 2 }, as: :json

    expect(response).to have_http_status(:ok)
    expect(session.reload.status).to eq("abandoned")
  end

  it "clears puzzle scenarios when the last consequence is removed" do
    stub_beta_catalog_feature_flags(
      "beta_source_puzzle" => true,
      "beta_action_puzzle" => true,
      "beta_action_leverage_photo" => true,
      "beta_action_chaster" => true
    )
    config = beta.ensure_puzzle_config!
    config.assign_scenarios!(
      ScenarioSet.from_params(
        {
          "scenarios" => [
            {
              "event" => "abandoned",
              "trigger" => {},
              "actions" => [
                { "possibility_id" => "chaster.add_time", "config" => { "seconds" => 60 } }
              ]
            }
          ]
        },
        source: :puzzle
      )
    )
    config.save!

    # After the last card is removed in the UI, only the scenarios[present]
    # sentinel remains — the controller must still clear the stored set.
    patch beta_puzzle_config_path, params: {
      default_piece_count: config.default_piece_count,
      default_reference_mode: config.default_reference_mode,
      cooldown_seconds: config.cooldown_seconds,
      scenarios: { present: "1" }
    }

    expect(response).to redirect_to(beta_sources_puzzle_path)
    expect(config.reload.scenario_set).to be_empty
  end
end
