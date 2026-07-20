# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionCookieDomain do
  describe ".for_environment" do
    around do |example|
      original = ENV["APP_PUBLIC_BASE_URL"]
      example.run
    ensure
      if original.nil?
        ENV.delete("APP_PUBLIC_BASE_URL")
      else
        ENV["APP_PUBLIC_BASE_URL"] = original
      end
    end

    it "returns a parent domain in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      ENV["APP_PUBLIC_BASE_URL"] = "https://dominochain.app"

      expect(described_class.for_environment).to eq(".dominochain.app")
    end

    it "returns nil outside production" do
      allow(Rails.env).to receive(:production?).and_return(false)
      ENV["APP_PUBLIC_BASE_URL"] = "https://dominochain.app"

      expect(described_class.for_environment).to be_nil
    end
  end
end
