# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Showcase backdoor", type: :request do
  include ActiveJob::TestHelper

  let(:beta) { create(:user, :beta, nickname: "doorbeta") }

  describe "GET /showcase/:nickname/backdoor" do
    it "returns 200 when backdoor is enabled" do
      get showcase_backdoor_path(beta.nickname)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 when backdoor is disabled" do
      beta.update!(showcase_backdoor_enabled: false)
      get showcase_backdoor_path(beta.nickname)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /showcase/:nickname/backdoor/add_time" do
    let(:service) { instance_double(ChasterService) }

    before do
      allow(ChasterService).to receive(:new).with(beta).and_return(service)
      allow(service).to receive(:current_lock).and_return({ id: "lock123" })
      allow(service).to receive(:add_time_to_lock).with("lock123", 3_660)
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
      expect(JSON.parse(response.body)["ok"]).to be true
      rec = beta.showcase_time_additions.last
      expect(rec.player_name).to eq("Visitor")
      expect(rec.message).to eq("Hello beta")
      expect(rec.seconds).to eq(3_660)
      expect(rec.chaster_applied).to be true
    end

    it "returns 404 when backdoor is disabled" do
      beta.update!(showcase_backdoor_enabled: false)
      post showcase_backdoor_add_time_path(beta.nickname),
        params: { days: 0, hours: 0, minutes: 5, player_name: "A", message: "B" },
        as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
