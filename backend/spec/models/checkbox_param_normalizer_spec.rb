# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckboxParamNormalizer do
  describe ".to_bool" do
    it "casts checked HTML checkbox params to true" do
      expect(described_class.to_bool([ "0", "1" ])).to be true
    end

    it "casts unchecked HTML checkbox params to false" do
      expect(described_class.to_bool("0")).to be false
    end

    it "does not treat a lone hidden array value as enabled" do
      expect(described_class.to_bool([ "0" ])).to be false
    end
  end
end
