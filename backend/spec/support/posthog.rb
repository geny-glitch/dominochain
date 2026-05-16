# frozen_string_literal: true

module PosthogFeatureFlagHelpers
  def build_feature_flag_evaluations(overrides = {})
    normalized = overrides.stringify_keys
    Class.new do
      define_method(:initialize) { |values| @values = values }
      define_method(:enabled?) { |key| @values.fetch(key.to_s, true) }
    end.new(normalized)
  end

  def default_feature_flag_map(overrides = {})
    BetaCatalog.expected_feature_flags.index_with(true).merge(overrides.stringify_keys)
  end

  def stub_beta_catalog_feature_flags(overrides = {})
    allow_any_instance_of(BetaCatalog).to receive(:evaluate_feature_flags).and_return(
      default_feature_flag_map(overrides)
    )
  end
end

RSpec.configure do |config|
  config.include PosthogFeatureFlagHelpers

  config.before do
    Rails.cache.clear

    allow_any_instance_of(BetaCatalog).to receive(:evaluate_feature_flags).and_return(
      default_feature_flag_map
    )
    allow(PostHog).to receive(:capture)
    allow(PostHog).to receive(:identify)
  end
end
