# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Strava goal page", type: :request do
  let(:beta) { create(:user, :beta, strava_access_token: "token", strava_refresh_token: "refresh") }
  let(:goal) { create(:strava_goal, user: beta, name: "Morning runs", required_activity_count: 2) }

  before do
    stub_beta_catalog_feature_flags("beta_source_strava" => true)
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "strava" => true } }
      )
    )
    sign_in beta
  end

  it "renders the goal detail page" do
    strava_service = instance_double(StravaService)
    allow(StravaService).to receive(:new).with(beta).and_return(strava_service)
    allow(strava_service).to receive(:activities_between).and_return([])

    get beta_strava_goal_show_path(goal)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(goal.name)
    expect(response.body).to include(I18n.t("beta.strava.goal_page.preview_check"))
    expect(response.body).to include(I18n.t("beta.strava.goal_page.activities_title"))
  end

  it "runs a preview check without persisting" do
    strava_service = instance_double(StravaService)
    allow(StravaService).to receive(:new).with(beta).and_return(strava_service)
    allow(strava_service).to receive(:activities_between).and_return([
      { id: 1, name: "Run", type: "Run", sport_type: "Run", duration_seconds: 3600, calories: 500, device_name: "Garmin", started_at: 1.day.ago }
    ])

    expect {
      post beta_strava_goal_preview_check_path(goal)
    }.not_to change { goal.strava_goal_checks.count }

    expect(response).to redirect_to(beta_strava_goal_show_path(goal))
    follow_redirect!
    expect(response.body).to include(I18n.t("beta.strava.goal_page.preview_hint"))
  end

  it "lists only eligible activities by default" do
    strava_service = instance_double(StravaService)
    allow(StravaService).to receive(:new).with(beta).and_return(strava_service)
    allow(strava_service).to receive(:activities_between).and_return([
      { id: 1, name: "Good run", type: "Run", sport_type: "Run", duration_seconds: 3600, calories: nil, device_name: "", started_at: 1.day.ago },
      { id: 2, name: "Short run", type: "Run", sport_type: "Run", duration_seconds: 600, calories: nil, device_name: "", started_at: 2.days.ago }
    ])

    get beta_strava_goal_show_path(goal)

    expect(response.body).to include("Good run")
    expect(response.body).not_to include("Short run")
  end

  it "still renders when Strava activities cannot be fetched" do
    strava_service = instance_double(StravaService)
    allow(StravaService).to receive(:new).with(beta).and_return(strava_service)
    allow(strava_service).to receive(:activities_between).and_raise(StravaService::Unauthorized, "Strava non autorisé")

    get beta_strava_goal_show_path(goal)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(goal.name)
    expect(response.body).to include(I18n.t("beta.strava.goal_page.activities_unauthorized"))
  end
end
