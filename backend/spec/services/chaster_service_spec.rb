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
    it "returns true when the lock has an end date" do
      expect(described_class.freeze_supported?(
        "limitLockTime" => true,
        "endDate" => 1.hour.from_now.iso8601,
        "role" => "wearer"
      )).to eq(true)
    end

    it "returns true when limitLockTime is false but an end date is present" do
      expect(described_class.freeze_supported?(
        "limitLockTime" => false,
        "endDate" => 1.hour.from_now.iso8601,
        "role" => "wearer"
      )).to eq(true)
    end

    it "returns true when the lock has a keyholder and an end date" do
      expect(described_class.freeze_supported?(
        "limitLockTime" => true,
        "endDate" => 1.hour.from_now.iso8601,
        "role" => "keyholder",
        "keyholder" => { "_id" => "kh-1" }
      )).to eq(true)
    end

    it "returns false when the lock has no end date" do
      expect(described_class.freeze_supported?(
        "limitLockTime" => false,
        "endDate" => nil,
        "role" => "wearer"
      )).to eq(false)
    end

    it "returns false for visitor locks" do
      expect(described_class.freeze_supported?(
        "endDate" => 1.hour.from_now.iso8601,
        "role" => "visitor"
      )).to eq(false)
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

    it "uses the extensions session action API for wearer locks" do
      service.freeze_lock(lock_id)

      expect(requests.length).to eq(1)
      expect(requests.first.path).to eq("/api/extensions/sessions/#{lock_id}/action")
      expect(JSON.parse(requests.first.body)).to eq("action" => { "name" => "freeze" })
    end

    it "uses the locks freeze endpoint for keyholder locks" do
      user.chaster_locks.find_by!(chaster_lock_id: lock_id).update!(
        raw_data: { "role" => "keyholder", "endDate" => 1.hour.from_now.iso8601 }
      )

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

    it "uses the extensions session action API for wearer locks" do
      service.unfreeze_lock(lock_id)

      expect(requests.length).to eq(1)
      expect(requests.first.path).to eq("/api/extensions/sessions/#{lock_id}/action")
      expect(JSON.parse(requests.first.body)).to eq("action" => { "name" => "unfreeze" })
    end
  end
end
