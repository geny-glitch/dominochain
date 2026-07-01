# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngineIndexing do
  describe ".production?" do
    it "is false in test" do
      expect(described_class.production?).to be(false)
    end

    it "is false when BG_ENV is staging even in production mode" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      previous = ENV["BG_ENV"]
      ENV["BG_ENV"] = "staging"

      expect(described_class.production?).to be(false)
    ensure
      if previous.nil?
        ENV.delete("BG_ENV")
      else
        ENV["BG_ENV"] = previous
      end
    end

    it "is true in production without staging BG_ENV" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      previous = ENV["BG_ENV"]
      ENV.delete("BG_ENV")

      expect(described_class.production?).to be(true)
    ensure
      if previous.nil?
        ENV.delete("BG_ENV")
      else
        ENV["BG_ENV"] = previous
      end
    end
  end

  describe ".page_indexable?" do
    it "is true only for the production homepage" do
      allow(described_class).to receive(:production?).and_return(true)

      expect(described_class.page_indexable?(controller_name: "home", action_name: "index")).to be(true)
      expect(described_class.page_indexable?(controller_name: "home", action_name: "show")).to be(false)
      expect(described_class.page_indexable?(controller_name: "sessions", action_name: "new")).to be(false)
    end

    it "is false outside production" do
      allow(described_class).to receive(:production?).and_return(false)

      expect(described_class.page_indexable?(controller_name: "home", action_name: "index")).to be(false)
    end
  end

  describe ".robots_txt_body" do
    it "blocks all crawlers outside production" do
      allow(described_class).to receive(:production?).and_return(false)

      expect(described_class.robots_txt_body).to include("Disallow: /")
      expect(described_class.robots_txt_body).not_to include("Allow:")
    end

    it "allows only the homepage in production" do
      allow(described_class).to receive(:production?).and_return(true)

      expect(described_class.robots_txt_body).to include("Disallow: /")
      expect(described_class.robots_txt_body).to include("Allow: /$")
    end
  end
end
