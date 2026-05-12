# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API cigarette entries", type: :request do
  let(:beta) do
    create(:user, :beta, showcase_snake_seconds_per_fruit: 120).tap do |user|
      user.update!(
        beta_ui_prefs: {
          "catalog_visibility" => {
            "sources" => { "cigarettes" => true },
            "actions" => { "chaster" => true }
          }
        }
      )
    end
  end
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
    allow(PostHog).to receive(:capture)
    allow(PostHog).to receive(:evaluate_flags).and_return(feature_flag_evaluations)
  end

  describe "GET /api/cigarettes" do
    it "returns today count and daily history" do
      travel_to Time.zone.parse("2026-04-30 09:30:00") do
        create(:cigarette_entry, user: beta, smoked_on: Date.current, smoked_at: 1.hour.ago, count: 2, chaster_seconds: 120, chaster_applied: true)
        create(:cigarette_entry, user: beta, smoked_on: Date.yesterday, smoked_at: 1.day.ago, count: 1, chaster_seconds: 120, chaster_applied: true)

        get api_cigarettes_path, headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["today_count"]).to eq(2)
        expect(json["seconds_per_cigarette"]).to eq(120)
        expect(json["history"].first).to include("date" => "2026-04-30", "count" => 2, "chaster_seconds" => 240)
        expect(json["history"].second).to include("date" => "2026-04-29", "count" => 1, "chaster_seconds" => 120)
      end
    end

    it "returns 401 without auth" do
      get api_cigarettes_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/cigarettes" do
    let(:service) { instance_double(ChasterService) }

    before do
      allow(ChasterService).to receive(:new).with(beta).and_return(service)
      allow(service).to receive(:current_lock).and_return({ id: "lock-cig" })
      allow(service).to receive(:add_time_to_lock)
    end

    it "stores the cigarette and adds configured seconds to Chaster" do
      travel_to Time.zone.parse("2026-04-30 09:30:00") do
        post api_cigarettes_path, params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(service).to have_received(:add_time_to_lock).with("lock-cig", 120)
        entry = beta.cigarette_entries.last
        expect(entry.smoked_on).to eq(Date.new(2026, 4, 30))
        expect(entry.chaster_seconds).to eq(120)
        expect(entry.chaster_applied).to be true

        json = JSON.parse(response.body)
        expect(json["today_count"]).to eq(1)
        expect(json["entry"]).to include("count" => 1, "chaster_applied" => true)
      end
    end

    it "keeps the entry with an error when Chaster has no active lock" do
      allow(service).to receive(:current_lock).and_return(nil)

      post api_cigarettes_path, params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["entry"]["chaster_applied"]).to be false
      expect(json["entry"]["chaster_error"]).to eq("Aucun cadenas Chaster actif.")
      expect(beta.cigarette_entries.last.chaster_applied).to be false
    end

    it "keeps the entry without applying time when cigarettes source is disabled in catalog" do
      beta.update!(beta_ui_prefs: { "catalog_visibility" => { "sources" => { "cigarettes" => false } } })

      post api_cigarettes_path, params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(service).not_to have_received(:add_time_to_lock)

      json = JSON.parse(response.body)
      expect(json["entry"]["chaster_applied"]).to be false
      expect(json["entry"]["chaster_error"]).to eq("Source ou action désactivée.")
    end

    it "keeps the entry without applying time when chaster action is disabled in catalog" do
      beta.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => false } } })

      post api_cigarettes_path, params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(service).not_to have_received(:add_time_to_lock)

      json = JSON.parse(response.body)
      expect(json["entry"]["chaster_applied"]).to be false
      expect(json["entry"]["chaster_error"]).to eq("Source ou action désactivée.")
    end

    context "when cigarettes source feature flag is disabled" do
      let(:feature_flag_overrides) { { "beta_source_cigarettes_enabled" => false } }

      it "keeps the entry without applying Chaster time" do
        post api_cigarettes_path, params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(service).not_to have_received(:add_time_to_lock)

        json = JSON.parse(response.body)
        expect(json["entry"]["chaster_applied"]).to be false
        expect(json["entry"]["chaster_error"]).to eq("Source ou action désactivée.")
      end
    end
  end
end
