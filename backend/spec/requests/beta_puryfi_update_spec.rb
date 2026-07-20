# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Beta PuryFi update", type: :request do
  let(:beta) { create(:user, :beta) }

  before do
    sign_in beta
    stub_beta_catalog_feature_flags
  end

  it "autosaves a single label seconds value as JSON" do
    patch beta_puryfi_path,
      params: { puryfi_seconds_per_label: { "0" => 42 } },
      headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("ok" => true)
    expect(beta.reload.puryfi_seconds_per_label["0"]).to eq(42)
  end

  it "autosaves a single shock level as JSON" do
    patch beta_puryfi_path,
      params: { puryfi_shock_level_per_label: { "3" => 2 } },
      headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(PuryfiConfig.shock_level_for_label(beta.reload, 3)).to eq(2)
  end
end
