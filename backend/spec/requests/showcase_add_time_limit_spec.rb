# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Showcase add_time rate limit", type: :request do
  let(:beta) { create(:user, :beta, nickname: "limbeta") }
  let(:service_double) { instance_double(ChasterService) }

  before do
    allow(ChasterService).to receive(:new).with(beta).and_return(service_double)
    allow(service_double).to receive(:current_lock).and_return({ id: "lock-1" })
    allow(service_double).to receive(:add_time_to_lock)
    ShowcaseAddTimeLimiter.reset_window!(beta.id)
  end

  it "returns 429 when showcase would exceed 2 days in 5 minutes" do
    travel_to Time.zone.parse("2026-04-25 12:00:00") do
      ShowcaseAddTimeEvent.create!(user: beta, seconds: ShowcaseAddTimeLimiter::MAX_SECONDS_PER_WINDOW)
    end

    post showcase_add_time_path(beta.nickname),
      params: { game_type: "snake" },
      headers: { "CONTENT_TYPE" => "application/json" },
      as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(service_double).not_to have_received(:add_time_to_lock)
  end

  it "records usage after successful snake add_time" do
    post showcase_add_time_path(beta.nickname),
      params: { game_type: "snake" },
      headers: { "CONTENT_TYPE" => "application/json" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(ShowcaseAddTimeEvent.where(user_id: beta.id).sum(:seconds)).to eq(ShowcaseController::SNAKE_SECONDS_PER_FRUIT)
  end

  it "uses beta-configured seconds per fruit for snake" do
    beta.update!(showcase_snake_seconds_per_fruit: 120)
    post showcase_add_time_path(beta.nickname),
      params: { game_type: "snake" },
      headers: { "CONTENT_TYPE" => "application/json" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(ShowcaseAddTimeEvent.where(user_id: beta.id).sum(:seconds)).to eq(120)
  end

  it "uses beta-configured seconds per obstacle for dino" do
    beta.update!(showcase_snake_seconds_per_fruit: 120)
    post showcase_add_time_path(beta.nickname),
      params: { game_type: "dino" },
      headers: { "CONTENT_TYPE" => "application/json" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(ShowcaseAddTimeEvent.where(user_id: beta.id).sum(:seconds)).to eq(120)
  end
end
