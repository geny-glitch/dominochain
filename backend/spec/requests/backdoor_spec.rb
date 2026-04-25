# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Backdoor", type: :request do
  let(:beta) { create(:user, :beta, nickname: "doorbeta") }
  let(:raw_token) { "test-secret-token-xyz" }

  before do
    beta.update!(backdoor_token_digest: Digest::SHA256.hexdigest(raw_token))
  end

  describe "GET /showcase/:nickname/backdoor/:token" do
    it "returns 404 when token is wrong" do
      get showcase_backdoor_path(beta.nickname, "wrong")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 200 when token matches" do
      get showcase_backdoor_path(beta.nickname, raw_token)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /showcase/:nickname/backdoor/:token/add_time" do
    let(:service_double) { instance_double(ChasterService) }

    before do
      allow(ChasterService).to receive(:new).with(beta).and_return(service_double)
      allow(service_double).to receive(:current_lock).and_return({ id: "lock-1" })
      allow(service_double).to receive(:add_time_to_lock).with("lock-1", 60)
    end

    it "adds time when under limit" do
      post showcase_backdoor_add_time_path(beta.nickname, raw_token),
        params: { seconds: 60 }.to_json,
        headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be true
      expect(service_double).to have_received(:add_time_to_lock).with("lock-1", 60)
      expect(ShowcaseAddTimeEvent.where(user_id: beta.id).sum(:seconds)).to eq(60)
    end

    it "returns 429 when sliding window would exceed 2 days" do
      ShowcaseAddTimeLimiter.reset_window!(beta.id)
      travel_to Time.zone.parse("2026-04-25 12:00:00") do
        ShowcaseAddTimeEvent.create!(user: beta, seconds: ShowcaseAddTimeLimiter::MAX_SECONDS_PER_WINDOW)
      end

      post showcase_backdoor_add_time_path(beta.nickname, raw_token),
        params: { seconds: 1 }.to_json,
        headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to be_present
      expect(body["remaining_seconds"]).to eq(0)
      expect(service_double).not_to have_received(:add_time_to_lock)
    end
  end
end
