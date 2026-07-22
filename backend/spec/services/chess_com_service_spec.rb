# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChessComService do
  let(:queue) { [] }

  before do
    allow(Net::HTTP).to receive(:start) do |hostname, *_args, **_kwargs, &block|
      expect(hostname).to eq("api.chess.com")
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { queue.shift }
      block&.call(http)
    end
  end

  def resp(code, body:, success: nil)
    code_s = code.to_s
    success = code_s.start_with?("2") if success.nil?
    r = instance_double(Net::HTTPResponse, body: body, code: code_s)
    allow(r).to receive(:is_a?) do |klass|
      if klass == Net::HTTPSuccess
        success
      elsif klass == Net::HTTPNotFound
        code_s == "404"
      else
        false
      end
    end
    r
  end

  describe ".normalize_username" do
    it "lowercases and strips" do
      expect(described_class.normalize_username("  Hikaru ")).to eq("hikaru")
    end
  end

  describe ".current_rating" do
    it "reads last rating for a time control" do
      stats = { "chess_blitz" => { "last" => { "rating" => 1500 } } }
      expect(described_class.current_rating(stats, "blitz")).to eq(1500)
    end
  end

  describe "#fetch_profile" do
    it "returns the parsed profile" do
      queue << resp(200, body: { "username" => "hikaru", "player_id" => 42, "location" => "Florida" }.to_json)

      profile = described_class.new.fetch_profile("Hikaru")
      expect(profile["player_id"]).to eq(42)
    end

    it "raises NotFound for unknown usernames" do
      queue << resp(404, body: { "message" => "Not found" }.to_json, success: false)

      expect { described_class.new.fetch_profile("missing") }.to raise_error(ChessComService::NotFound)
    end
  end

  describe "#verify_location!" do
    it "accepts when the location contains the code" do
      queue << resp(200, body: { "username" => "me", "player_id" => 7, "location" => "Paris BG-ABC123" }.to_json)

      profile = described_class.new.verify_location!("me", "BG-ABC123")
      expect(profile["player_id"]).to eq(7)
    end

    it "rejects when the code is missing" do
      queue << resp(200, body: { "username" => "me", "player_id" => 7, "location" => "Paris" }.to_json)

      expect {
        described_class.new.verify_location!("me", "BG-ABC123")
      }.to raise_error(ChessComService::Error, /not found/i)
    end
  end

  describe "#current_rating_for!" do
    it "raises when the rating type is missing" do
      queue << resp(200, body: { "chess_rapid" => { "last" => { "rating" => 1200 } } }.to_json)

      expect {
        described_class.new.current_rating_for!("me", "blitz")
      }.to raise_error(ChessComService::RatingUnavailable)
    end
  end
end
