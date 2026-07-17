# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::ShowcaseGameAddTime do
  let(:beta) do
    create(:user, :beta, nickname: "evbeta").tap do |user|
      user.update!(
        showcase_snake_enabled: true,
        beta_ui_prefs: {
          "catalog_visibility" => {
            "sources" => { "showcase" => true },
            "actions" => { "chaster" => true, "pishock" => true }
          }
        }
      )
    end
  end

  before do
    stub_beta_catalog_feature_flags
    allow(ChasterService).to receive(:new).with(beta).and_return(chaster_double)
    allow(chaster_double).to receive(:current_lock).and_return({ id: "lock-1" })
    allow(chaster_double).to receive(:add_time_to_lock)
    ShowcaseAddTimeLimiter.reset_window!(beta.id)
  end

  let(:chaster_double) { instance_double(ChasterService) }

  it "runs consequence pipeline for snake" do
    result = described_class.call(beta: beta, game_kind: "snake", seconds: 300, as_json: true)
    expect(result.ok).to be true
    expect(chaster_double).to have_received(:add_time_to_lock).with(
      "lock-1",
      300,
      hash_including(source: "showcase_game")
    )
    expect(ShowcaseAddTimeEvent.where(user_id: beta.id).sum(:seconds)).to eq(300)
  end

  it "returns not found when game disabled" do
    beta.update!(showcase_snake_enabled: false, showcase_quiz_enabled: true)
    result = described_class.call(beta: beta, game_kind: "snake", seconds: 300, as_json: true)
    expect(result.ok).to be false
    expect(result.http_status).to eq(:not_found)
  end

  it "returns unprocessable when showcase source is disabled in catalog" do
    beta.update!(beta_ui_prefs: { "catalog_visibility" => { "sources" => { "showcase" => false } } })

    result = described_class.call(beta: beta, game_kind: "snake", seconds: 300, as_json: true)

    expect(result.ok).to be false
    expect(result.http_status).to eq(:unprocessable_entity)
    expect(result.json_body).to include(error: "Source ou action désactivée.")
    expect(chaster_double).not_to have_received(:add_time_to_lock)
  end

  it "returns unprocessable when all showcase actions are disabled in catalog" do
    beta.update!(
      beta_ui_prefs: {
        "catalog_visibility" => {
          "sources" => { "showcase" => true },
          "actions" => { "chaster" => false, "pishock" => false }
        }
      }
    )

    result = described_class.call(beta: beta, game_kind: "snake", seconds: 300, as_json: true)

    expect(result.ok).to be false
    expect(result.http_status).to eq(:unprocessable_entity)
    expect(result.json_body).to include(error: "Source ou action désactivée.")
    expect(chaster_double).not_to have_received(:add_time_to_lock)
  end
end
