# frozen_string_literal: true

require "rails_helper"

RSpec.describe "time zone account update", type: :request do
  it "persists a new zone with update_columns and shows location-first labels" do
    beta = create(:user, :beta, time_zone: "Paris")
    sign_in beta

    patch user_time_zone_path, params: { account_tz: "Quito" }
    expect(response).to redirect_to(beta_account_path)
    expect(beta.reload.time_zone).to eq("Quito")

    follow_redirect!
    expect(response.body).to include("Currently saved:")
    expect(response.body).to include("Quito (GMT")
    expect(response.body).to include('<option selected="selected" value="Quito">')
    expect(response.body).to include(">Paris (GMT")
    expect(response.body).not_to include(">(GMT+")
  end

  it "can change away from Paris repeatedly" do
    beta = create(:user, :beta, time_zone: "Paris")
    sign_in beta

    patch user_time_zone_path, params: { account_tz: "London" }
    expect(beta.reload.time_zone).to eq("London")

    patch user_time_zone_path, params: { account_tz: "Berlin" }
    expect(beta.reload.time_zone).to eq("Berlin")

    patch user_time_zone_path, params: { account_tz: "Paris" }
    expect(beta.reload.time_zone).to eq("Paris")
  end
end
