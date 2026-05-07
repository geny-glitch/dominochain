# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaService do
  let(:queue) { [] }

  before do
    allow(Net::HTTP).to receive(:start) do |hostname, *_args, **_kwargs, &block|
      expect(hostname).to eq("www.strava.com")
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { queue.shift }
      block&.call(http)
    end
  end

  def resp(code, body:, success: nil)
    code_s = code.to_s
    success = code_s.start_with?("2") if success.nil?
    r = instance_double(Net::HTTPResponse, body: body, code: code_s)
    allow(r).to receive(:is_a?) { |klass| klass == Net::HTTPSuccess ? success : false }
    r
  end

  describe "#activities_between" do
    it "fetches pages and normalizes Strava activities" do
      user = create(:user, strava_access_token: "access")
      stub_const("#{described_class}::ACTIVITIES_PER_PAGE", 2)
      queue << resp(
        200,
        body: [
          { "id" => 1, "name" => "Run", "type" => "Run", "sport_type" => "Run", "moving_time" => 1800, "start_date" => "2026-05-01T08:00:00Z" },
          { "id" => 2, "name" => "Ride", "type" => "Ride", "elapsed_time" => 3600, "start_date" => "2026-05-02T08:00:00Z" }
        ].to_json
      )
      queue << resp(200, body: [ { "id" => 3, "name" => "Walk", "type" => "Walk", "moving_time" => 900 } ].to_json)

      activities = described_class.new(user).activities_between(
        start_time: Time.zone.parse("2026-04-27"),
        end_time: Time.zone.parse("2026-05-04")
      )

      expect(activities.map { |a| a[:id] }).to eq([ 1, 2, 3 ])
      expect(activities.first).to include(type: "Run", duration_seconds: 1800)
    end

    it "refreshes the token when Strava returns 401" do
      user = create(:user, strava_access_token: "old", strava_refresh_token: "refresh")
      allow(described_class).to receive(:configured?).and_return(true)
      allow(described_class).to receive(:client_id).and_return("client")
      allow(described_class).to receive(:client_secret).and_return("secret")
      queue << resp(401, body: { "message" => "Authorization Error" }.to_json, success: false)
      queue << resp(200, body: { "access_token" => "new", "refresh_token" => "new-refresh", "expires_at" => 1.hour.from_now.to_i }.to_json)
      queue << resp(200, body: [].to_json)

      activities = described_class.new(user).activities_between(
        start_time: Time.zone.parse("2026-04-27"),
        end_time: Time.zone.parse("2026-05-04")
      )

      expect(activities).to eq([])
      expect(user.reload.strava_access_token).to eq("new")
    end
  end
end
