# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChasterService do
  describe "#add_time_to_lock" do
    let(:user) { create(:user, :beta, chaster_access_token: "token") }
    let(:service) { described_class.new(user) }
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
    end

    it "does not call Chaster API when chaster action is disabled in catalog" do
      user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => false } } })
      expect(Net::HTTP).not_to receive(:start)

      expect do
        service.add_time_to_lock("lock-1", 60)
      end.to raise_error(ChasterService::Error, "Chaster action disabled")
    end

    it "tracks time_added in PostHog after a successful Chaster update" do
      user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => true } } })
      response = instance_double(Net::HTTPResponse, code: "200", body: "{}")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      service.add_time_to_lock("lock-1", 90, source: "puryfi", summary: "PuryFi")

      expect(PostHog).to have_received(:capture).with(
        distinct_id: user.posthog_distinct_id,
        event: "time_added",
        properties: { seconds: 90, reason: "puryfi", source: "puryfi" }
      )
    end

    context "when chaster feature flag is disabled" do
      let(:feature_flag_overrides) { { "beta_action_chaster" => false } }

      it "still blocks if catalog action remains disabled" do
        user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => false } } })
        expect(Net::HTTP).not_to receive(:start)

        expect do
          service.add_time_to_lock("lock-1", 60)
        end.to raise_error(ChasterService::Error, "Chaster action disabled")
      end
    end
  end

  describe ".freeze_supported?" do
    it "returns false while freeze UI is disabled" do
      expect(described_class.freeze_supported?(
        "limitLockTime" => true,
        "endDate" => 1.hour.from_now.iso8601,
        "role" => "keyholder"
      )).to eq(false)
    end
  end

  describe ".freeze_ui_enabled?" do
    it "is disabled for now" do
      expect(described_class.freeze_ui_enabled?).to eq(false)
    end
  end

  describe "#freeze_lock" do
    let(:user) { create(:user, :beta, chaster_access_token: "token") }
    let(:service) { described_class.new(user) }
    let(:lock_id) { "lock-1" }
    let(:requests) { [] }

    before do
      stub_beta_catalog_feature_flags({})
      user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => true } } })
      ChasterLock.create!(
        user: user,
        chaster_lock_id: lock_id,
        status: "locked",
        raw_data: { "role" => "wearer", "endDate" => 1.hour.from_now.iso8601 }
      )

      allow(Net::HTTP).to receive(:start) do |hostname, *_args, **_kwargs, &block|
        expect(hostname).to eq("api.chaster.app")
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |req| requests << req; chaster_response }
        block&.call(http)
      end
    end

    def chaster_response
      response = instance_double(Net::HTTPResponse, code: "201", body: "{}")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      response
    end

    it "uses the locks freeze endpoint" do
      service.freeze_lock(lock_id)

      expect(requests.length).to eq(1)
      expect(requests.first.path).to eq("/locks/#{lock_id}/freeze")
      expect(JSON.parse(requests.first.body)).to eq("isFrozen" => true)
    end
  end

  describe "#unfreeze_lock" do
    let(:user) { create(:user, :beta, chaster_access_token: "token") }
    let(:service) { described_class.new(user) }
    let(:lock_id) { "lock-1" }
    let(:requests) { [] }

    before do
      stub_beta_catalog_feature_flags({})
      user.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => true } } })
      ChasterLock.create!(
        user: user,
        chaster_lock_id: lock_id,
        status: "locked",
        raw_data: { "role" => "wearer", "endDate" => 1.hour.from_now.iso8601 }
      )

      allow(Net::HTTP).to receive(:start) do |hostname, *_args, **_kwargs, &block|
        expect(hostname).to eq("api.chaster.app")
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |req| requests << req; chaster_response }
        block&.call(http)
      end
    end

    def chaster_response
      response = instance_double(Net::HTTPResponse, code: "201", body: "{}")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      response
    end

    it "uses the locks freeze endpoint with isFrozen false" do
      service.unfreeze_lock(lock_id)

      expect(requests.length).to eq(1)
      expect(requests.first.path).to eq("/locks/#{lock_id}/freeze")
      expect(JSON.parse(requests.first.body)).to eq("isFrozen" => false)
    end
  end
end
