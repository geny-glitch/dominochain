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
end
