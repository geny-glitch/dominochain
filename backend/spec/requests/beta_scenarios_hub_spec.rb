# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Beta scenarios hub", type: :request do
  let(:beta) { create(:user, :beta) }

  before do
    stub_beta_catalog_feature_flags(
      "beta_source_wallpaper" => true,
      "beta_source_cornertime" => true,
      "beta_source_strava" => true,
      "beta_action_chaster" => true
    )
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => {
          "sources" => { "wallpaper" => true, "cornertime" => true, "strava" => true },
          "actions" => { "chaster" => true }
        }
      )
    )
    sign_in beta
  end

  it "renders aggregated scenarios from wallpaper and cornertime" do
    wallpaper = beta.ensure_wallpaper_enforcement_config!
    wallpaper.assign_scenarios!(
      ScenarioSet.from_params(
        {
          "scenarios" => [
            {
              "event" => "mismatch",
              "trigger" => { "delay_minutes" => "10", "mode" => "strict" },
              "actions" => [ { "possibility_id" => "chaster.add_time", "config" => { "seconds" => "60" } } ]
            }
          ]
        },
        source: :wallpaper
      )
    )
    wallpaper.save!

    cornertime = beta.ensure_cornertime_config!
    cornertime.assign_scenarios!(
      ScenarioSet.from_params(
        {
          "scenarios" => [
            {
              "event" => "movement_detected",
              "trigger" => {},
              "actions" => [ { "possibility_id" => "chaster.add_time", "config" => { "seconds" => "120" } } ]
            }
          ]
        },
        source: :cornertime
      )
    )
    cornertime.save!

    get beta_scenarios_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("beta.scenarios.events.mismatch.label"))
    expect(response.body).to include(I18n.t("beta.scenarios.events.movement_detected.label"))
    expect(response.body).to include(I18n.t("beta.scenarios.hub.sources.wallpaper"))
    expect(response.body).to include(I18n.t("beta.scenarios.hub.sources.cornertime"))
  end

  it "creates a cornertime scenario from the hub" do
    beta.ensure_cornertime_config!

    post beta_scenarios_create_path, params: {
      source: "cornertime",
      scenarios: {
        scenarios: {
          "0" => {
            event: "early_stop",
            trigger: {},
            actions: {
              "0" => {
                possibility_id: "chaster.add_time",
                config: { seconds: "300" }
              }
            }
          }
        }
      }
    }

    expect(response).to redirect_to(beta_scenarios_path)
    config = beta.ensure_cornertime_config!.reload
    scenario = config.scenario_for("early_stop")
    expect(scenario).to be_present
    expect(scenario.actions.first[:possibility_id]).to eq("chaster.add_time")
  end

  it "creates a strava goal scenario from the hub" do
    goal = create(:strava_goal, user: beta, chaster_penalty_seconds: 0)
    beta.ensure_strava_config!

    post beta_scenarios_create_path, params: {
      source: "strava",
      scenarios: {
        scenarios: {
          "0" => {
            event: "goal_failed",
            trigger: { goal_id: goal.id },
            actions: {
              "0" => {
                possibility_id: "chaster.add_time",
                config: { seconds: "1800" }
              }
            }
          }
        }
      }
    }

    expect(response).to redirect_to(beta_scenarios_path)
    config = beta.ensure_strava_config!.reload
    scenario = config.scenario_set.for_event_and_goal("goal_failed", goal_id: goal.id)
    expect(scenario).to be_present
    expect(scenario.actions.first[:possibility_id]).to eq("chaster.add_time")
  end

  it "creates an any-goal strava scenario from the hub" do
    beta.ensure_strava_config!

    post beta_scenarios_create_path, params: {
      source: "strava",
      scenarios: {
        scenarios: {
          "0" => {
            event: "any_goal_failed",
            trigger: {},
            actions: {
              "0" => {
                possibility_id: "chaster.add_time",
                config: { seconds: "600" }
              }
            }
          }
        }
      }
    }

    expect(response).to redirect_to(beta_scenarios_path)
    config = beta.ensure_strava_config!.reload
    expect(config.scenario_for("any_goal_failed")).to be_present
  end
end
