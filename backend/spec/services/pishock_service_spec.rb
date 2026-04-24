# frozen_string_literal: true

require "rails_helper"

RSpec.describe PishockService do
  describe "#shock" do
    it "returns :skipped when disabled" do
      user = create(:user, pishock_enabled: false, pishock_username: "u", pishock_api_key: "k", pishock_share_code: "c")
      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:skipped)
    end

    it "returns :skipped when credentials incomplete" do
      user = create(:user, pishock_enabled: true, pishock_username: "u", pishock_api_key: "", pishock_share_code: "c")
      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:skipped)
    end

    it "returns :ok when API responds with Operation Succeeded" do
      user = create(:user, pishock_enabled: true, pishock_username: "u", pishock_api_key: "k", pishock_share_code: "c")
      res = double("response",
        body: "Operation Succeeded.")
      allow(res).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(res)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect(described_class.new(user).shock(intensity: 5, duration: 2)).to eq(:ok)
    end

    it "returns :error when API body is not success" do
      user = create(:user, pishock_enabled: true, pishock_username: "u", pishock_api_key: "k", pishock_share_code: "c")
      res = double("response",
        body: "Device currently not connected.",
        code: "200")
      allow(res).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(res)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect(described_class.new(user).shock(intensity: 5, duration: 2)).to eq(:error)
    end

    it "maps fractional seconds to milliseconds like Python-PiShock" do
      user = create(:user, pishock_enabled: true, pishock_username: "u", pishock_api_key: "k", pishock_share_code: "c")
      svc = described_class.new(user)
      expect(svc.send(:normalize_duration, 0.2)).to eq(200)
      expect(svc.send(:normalize_duration, 1)).to eq(1)
    end

    it "returns :error on HTTP 404 (e.g. bad share code)" do
      user = create(:user, pishock_enabled: true, pishock_username: "u", pishock_api_key: "k", pishock_share_code: "c")
      res = instance_double(Net::HTTPNotFound, body: "", code: "404")
      allow(res).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(res)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:error)
    end
  end
end
