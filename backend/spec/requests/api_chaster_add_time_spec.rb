# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API chaster add_time", type: :request do
  let(:beta) { create(:user, :beta) }
  let(:device) { create(:device, user: beta) }
  let(:headers) { { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token } }
  let(:feature_flag_overrides) { {} }
  let(:feature_flag_evaluations) do
    Struct.new(:overrides) do
      def enabled?(key)
        overrides.fetch(key.to_s, true)
      end
    end.new(feature_flag_overrides)
  end

  before do
    allow(PostHog).to receive(:evaluate_flags).and_return(feature_flag_evaluations)
    allow(PostHog).to receive(:capture)
  end

  it "does not add Chaster time when chaster action is disabled by the user" do
    beta.update!(
      beta_ui_prefs: {
        "catalog_visibility" => {
          "sources" => { "puryfi" => true },
          "actions" => { "chaster" => false }
        }
      }
    )
    allow(ChasterService).to receive(:new)

    post api_chaster_add_time_path, params: { seconds: 120 }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error" => "Source ou action désactivée.")
    expect(ChasterService).not_to have_received(:new)
    expect(PostHog).not_to have_received(:capture)
  end

  context "when source feature flag is disabled" do
    let(:feature_flag_overrides) { { "beta_source_cigarettes_enabled" => false } }
    let(:service) { instance_double(ChasterService, current_lock: { id: "lock-1" }) }

    before do
      allow(service).to receive(:add_time_to_lock)
      allow(ChasterService).to receive(:new).with(beta).and_return(service)
    end

    it "does not add Chaster time for cigarette events" do
      post api_cigarettes_path, params: { count: 1 }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(service).not_to have_received(:add_time_to_lock)

      entry = beta.cigarette_entries.order(:id).last
      expect(entry.chaster_applied).to be(false)
      expect(entry.chaster_error).to eq("Source ou action désactivée.")
    end
  end
end
