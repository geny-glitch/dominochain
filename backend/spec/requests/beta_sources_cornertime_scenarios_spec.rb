# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Beta cornertime scenarios", type: :request do
  let(:beta) { create(:user, :beta) }

  before do
    stub_beta_catalog_feature_flags(
      "beta_source_cornertime" => true,
      "beta_action_chaster" => true
    )
    beta.update!(
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => {
          "sources" => { "cornertime" => true },
          "actions" => { "chaster" => true }
        }
      )
    )
    sign_in beta
  end

  it "persists scenarios JSONB from the cornertime config form" do
    config = beta.ensure_cornertime_config!

    patch beta_cornertime_config_path, params: {
      sensitivity: "medium",
      violation_cooldown_seconds: "8",
      calibration_seconds: "5",
      scenarios: {
        scenarios: {
          "0" => {
            event: "movement_detected",
            trigger: {},
            actions: {
              "0" => {
                possibility_id: "chaster.add_time",
                config: { seconds: "90" }
              }
            }
          }
        }
      }
    }

    expect(response).to redirect_to(beta_sources_cornertime_path)
    config.reload
    expect(config.scenario_for("movement_detected")).to be_present
    expect(config.movement_sanction_object.any_active?).to be true
  end

  it "builds scenarios from legacy sanctions when JSONB is empty" do
    config = beta.ensure_cornertime_config!
    config.update_columns(
      scenarios: { "scenarios" => [] },
      movement_sanction: {
        "items" => [
          { "possibility_id" => "chaster.add_time", "enabled" => true, "config" => { "seconds" => 45 } }
        ]
      },
      early_stop_sanction: { "items" => [] }
    )

    legacy = ScenarioSet.from_legacy_cornertime(config.reload)
    expect(legacy.for_event("movement_detected")).to be_present
    expect(config.scenario_set.for_event("movement_detected")).to be_present
  end
end
