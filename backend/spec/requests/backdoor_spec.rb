# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Showcase backdoor (legacy spec path)", type: :request do
  include ActiveJob::TestHelper

  let(:beta) { create(:user, :beta, nickname: "doorbeta") }

  before do
    beta.update!(
      showcase_backdoor_enabled: true,
      beta_ui_prefs: beta.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "showcase" => true }, "actions" => { "chaster" => true } }
      )
    )
  end

  describe "GET /showcase/:nickname/backdoor" do
    it "returns 200 when backdoor is enabled" do
      get showcase_backdoor_path(beta.nickname)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 when backdoor is disabled" do
      beta.update!(showcase_snake_enabled: true, showcase_backdoor_enabled: false)
      get showcase_backdoor_path(beta.nickname)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /showcase/:nickname/backdoor/add_time" do
    let(:service) { instance_double(ChasterService) }

    before do
      allow(ChasterService).to receive(:new).with(beta).and_return(service)
      allow(service).to receive(:current_lock).and_return({ id: "lock123" })
      allow(service).to receive(:add_time_to_lock).with(
        "lock123",
        3_660,
        source: "showcase_backdoor",
        summary: a_string_including("Visitor"),
        metadata: hash_including("player_name" => "Visitor", "message" => "Hello beta")
      )
    end

    it "stores addition, calls Chaster and enqueues FCM job" do
      expect do
        post showcase_backdoor_add_time_path(beta.nickname),
          params: {
            days: 0,
            hours: 1,
            minutes: 1,
            player_name: "Visitor",
            message: "Hello beta"
          },
          headers: { "Content-Type" => "application/json" },
          as: :json
      end.to have_enqueued_job(ShowcaseBackdoorNotifyJob).with(beta.id, "Visitor", 3_660, "Hello beta")

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be true
      expect(body["remaining_seconds"]).to be_a(Integer)
      rec = beta.showcase_time_additions.last
      expect(rec.player_name).to eq("Visitor")
      expect(rec.message).to eq("Hello beta")
      expect(rec.seconds).to eq(3_660)
      expect(rec.chaster_applied).to be true
    end

    it "returns 404 when backdoor is disabled" do
      beta.update!(showcase_snake_enabled: true, showcase_backdoor_enabled: false)
      post showcase_backdoor_add_time_path(beta.nickname),
        params: { days: 0, hours: 0, minutes: 5, player_name: "A", message: "B" },
        as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 429 when sliding window would exceed 2 days" do
      ShowcaseAddTimeLimiter.reset_window!(beta.id)
      travel_to Time.zone.parse("2026-04-25 12:00:00") do
        ShowcaseAddTimeEvent.create!(user: beta, seconds: ShowcaseAddTimeLimiter::MAX_SECONDS_PER_WINDOW)

        post showcase_backdoor_add_time_path(beta.nickname),
          params: { days: 0, hours: 0, minutes: 1, player_name: "A", message: "B" },
          as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(service).not_to have_received(:add_time_to_lock)
      end
    end
  end
end
