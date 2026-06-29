# frozen_string_literal: true

require "rails_helper"

RSpec.describe TigrisObjectStorage do
  describe ".prefixed_key" do
    it "adds ACTIVE_STORAGE_KEY_PREFIX when missing" do
      previous = ENV["ACTIVE_STORAGE_KEY_PREFIX"]
      ENV["ACTIVE_STORAGE_KEY_PREFIX"] = "staging/"

      expect(described_class.prefixed_key("abc123")).to eq("staging/abc123")
      expect(described_class.prefixed_key("staging/abc123")).to eq("staging/abc123")
    ensure
      ENV["ACTIVE_STORAGE_KEY_PREFIX"] = previous
    end
  end
end

RSpec.describe AndroidApkStorage do
  describe ".present?" do
    it "returns false when Tigris is not configured" do
      allow(TigrisObjectStorage).to receive(:configured?).and_return(false)

      expect(described_class.present?).to be(false)
    end
  end
end
