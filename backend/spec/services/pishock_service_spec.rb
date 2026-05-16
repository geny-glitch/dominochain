# frozen_string_literal: true

require "rails_helper"

RSpec.describe PishockService do
  let(:queue) { [] }
  let(:feature_flag_overrides) { {} }
  let(:feature_flag_evaluations) do
    Struct.new(:overrides) do
      def enabled?(key)
        overrides.fetch(key.to_s, true)
      end
    end.new(feature_flag_overrides)
  end

  before do
    stub_beta_catalog_feature_flags(feature_flag_overrides)
    allow(Net::HTTP).to receive(:start) do |hostname, *_args, **_kwargs, &block|
      expect(hostname).to eq("api.pishock.com")
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { queue.shift }
      block&.call(http)
    end
  end

  def resp(code, body: "", success: nil)
    code_s = code.to_s
    success = code_s.start_with?("2") if success.nil?
    r = instance_double(Net::HTTPResponse, body: body, code: code_s)
    allow(r).to receive(:is_a?).with(Net::HTTPSuccess).and_return(success)
    r
  end

  def create_pishock_user(**attrs)
    create(
      :user,
      {
        pishock_enabled: true,
        pishock_username: "u",
        pishock_api_key: "k",
        pishock_share_code: "c"
      }.merge(attrs)
    ).tap do |user|
      user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "pishock" => true } } })
    end
  end

  describe "#shock" do
    it "returns :skipped when disabled" do
      user = create_pishock_user(pishock_enabled: false)
      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:skipped)
    end

    it "returns :skipped when pishock action is disabled in catalog" do
      user = create_pishock_user
      user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "pishock" => false } } })
      expect(Net::HTTP).not_to receive(:start)

      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:skipped)
    end

    context "when pishock feature flag is disabled" do
      let(:feature_flag_overrides) { { "beta_action_pishock" => false } }

      it "returns :skipped without calling PiShock API" do
        user = create_pishock_user
        expect(Net::HTTP).not_to receive(:start)

        expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:skipped)
      end
    end

    it "returns :skipped when credentials incomplete" do
      user = create_pishock_user(pishock_api_key: "")
      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:skipped)
    end

    it "returns :ok when operate succeeds (204)" do
      user = create_pishock_user
      queue << resp(200, body: [{ "Id" => 999, "ShareCode" => "c" }].to_json)
      queue << resp(204, body: "")

      expect(described_class.new(user).shock(intensity: 5, duration: 2)).to eq(:ok)
    end

    it "returns :error when API body indicates failure (non-2xx operate)" do
      user = create_pishock_user
      queue << resp(200, body: [{ "Id" => 1, "ShareCode" => "c" }].to_json)
      queue << resp(503, body: "paused", success: false)

      expect(described_class.new(user).shock(intensity: 5, duration: 2)).to eq(:device_error)
    end

    it "maps fractional seconds to milliseconds like before" do
      user = create_pishock_user
      svc = described_class.new(user)
      expect(svc.send(:duration_to_milliseconds, 0.2)).to eq(200)
      expect(svc.send(:duration_to_milliseconds, 1)).to eq(1000)
    end

    it "returns :device_error on operate 404" do
      user = create_pishock_user
      queue << resp(200, body: [{ "Id" => 1, "ShareCode" => "c" }].to_json)
      queue << resp(404, body: "", success: false)

      expect(described_class.new(user).shock(intensity: 5, duration: 1)).to eq(:device_error)
    end
  end

  describe ".test_connection!" do
    let(:user) { create_pishock_user }

    it "returns :skipped when credentials incomplete" do
      incomplete = create_pishock_user(pishock_api_key: "")
      expect(described_class.test_connection!(user: incomplete)).to eq(:skipped)
    end

    it "returns :ok when Account, GetShared match, and beep succeed" do
      queue << resp(200, body: "{}")
      queue << resp(200, body: [{ "Id" => 42, "ShareCode" => "c" }].to_json)
      queue << resp(204, body: "")

      expect(described_class.test_connection!(user: user)).to eq(:ok)
    end

    it "returns :auth_error when GET /Account is 401" do
      queue << resp(401, body: "", success: false)
      expect(described_class.test_connection!(user: user)).to eq(:auth_error)
    end

    it "returns :device_error when share cannot be resolved" do
      queue << resp(200, body: "{}")
      queue << resp(200, body: [].to_json)
      queue << resp(404, body: "", success: false) # PUT /Share
      expect(described_class.test_connection!(user: user)).to eq(:device_error)
    end

    it "returns :device_error when operate fails" do
      queue << resp(200, body: "{}")
      queue << resp(200, body: [{ "Id" => 1, "ShareCode" => "c" }].to_json)
      queue << resp(405, body: "", success: false)

      expect(described_class.test_connection!(user: user)).to eq(:device_error)
    end

    it "returns :error when GET /Account is 500" do
      queue << resp(500, body: "err", success: false)
      expect(described_class.test_connection!(user: user)).to eq(:error)
    end

    it "claims share via PUT /Share then operates when not initially listed" do
      queue << resp(200, body: "{}")
      queue << resp(200, body: [].to_json)
      queue << resp(204, body: "") # PUT /Share
      queue << resp(200, body: [{ "Id" => 7, "ShareCode" => "c" }].to_json)
      queue << resp(204, body: "")

      expect(described_class.test_connection!(user: user)).to eq(:ok)
    end
  end
end
