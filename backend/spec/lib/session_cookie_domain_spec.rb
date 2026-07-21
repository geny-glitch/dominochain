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

  describe ".shared_cookie_options" do
    it "includes the shared domain in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(described_class).to receive(:for_environment).and_return(".dominochain.app")

      expect(described_class.shared_cookie_options).to eq(
        secure: true,
        same_site: :lax,
        domain: ".dominochain.app"
      )
    end
  end

  describe ".clear_host_only_auth_cookies" do
    it "deletes host-only auth cookies when a shared domain is configured" do
      cookies = instance_double(ActionDispatch::Cookies::CookieJar)
      allow(cookies).to receive(:delete)
      allow(described_class).to receive(:for_environment).and_return(".dominochain.app")
      allow(Rails.env).to receive(:production?).and_return(true)

      described_class.clear_host_only_auth_cookies(cookies)

      [described_class::SESSION_KEY, described_class::REMEMBER_KEY].each do |key|
        expect(cookies).to have_received(:delete).with(key, secure: true, same_site: :lax)
      end
    end

    it "does nothing when no shared domain is configured" do
      cookies = instance_double(ActionDispatch::Cookies::CookieJar, delete: true)
      allow(described_class).to receive(:for_environment).and_return(nil)

      described_class.clear_host_only_auth_cookies(cookies)

      expect(cookies).not_to have_received(:delete)
    end
  end

  describe ".clear_all_auth_cookies" do
    it "deletes host-only and shared-domain auth cookies" do
      cookies = instance_double(ActionDispatch::Cookies::CookieJar)
      allow(cookies).to receive(:delete)
      allow(described_class).to receive(:for_environment).and_return(".dominochain.app")
      allow(Rails.env).to receive(:production?).and_return(true)

      described_class.clear_all_auth_cookies(cookies)

      [described_class::SESSION_KEY, described_class::REMEMBER_KEY].each do |key|
        expect(cookies).to have_received(:delete).with(key, secure: true, same_site: :lax)
        expect(cookies).to have_received(:delete).with(
          key,
          secure: true,
          same_site: :lax,
          domain: ".dominochain.app"
        )
      end
    end
  end
end
