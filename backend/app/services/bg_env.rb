# frozen_string_literal: true

class BgEnv
  def self.posthog_value
    ENV.fetch("BG_ENV") { Rails.env.production? ? "production" : "development" }
  end

  def self.staging?
    posthog_value == "staging"
  end
end
