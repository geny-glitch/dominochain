# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api Pishock shock", type: :request do
  include ActiveJob::TestHelper

  let(:plugin_token) { "puryfi-shock-token" }
  let(:headers) { { "Authorization" => "Bearer #{plugin_token}" } }

  let!(:beta) do
    create(
      :user,
      :beta,
      puryfi_plugin_token: plugin_token,
      pishock_enabled: true,
      pishock_username: "u",
      pishock_share_code: "c",
      pishock_api_key: "k"
    )
  end

  before do
    beta.update!(
      beta_ui_prefs: {
        "catalog_visibility" => {
          "actions" => { "pishock" => true },
          "sources" => { "puryfi" => true }
        }
      }
    )
    stub_beta_catalog_feature_flags
  end

  it "enqueues a shock job for plugin token auth" do
    expect {
      post api_pishock_shock_path, params: { intensity: 30, duration: 2 }, headers: headers, as: :json
    }.to have_enqueued_job(PishockShockJob).with(beta.id, 30, 2)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("ok" => true, "intensity" => 30, "duration" => 2)
  end

  it "rejects when PiShock is disabled for the user" do
    beta.update!(pishock_enabled: false)

    expect {
      post api_pishock_shock_path, params: { intensity: 10, duration: 1 }, headers: headers, as: :json
    }.not_to have_enqueued_job(PishockShockJob)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
