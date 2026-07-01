# frozen_string_literal: true

class SearchEngineIndexing
  NOINDEX_DIRECTIVE = "noindex, nofollow, noarchive, nosnippet"

  def self.production?
    Rails.env.production? && ENV["BG_ENV"] != "staging"
  end

  def self.page_indexable?(controller_name:, action_name:)
    production? && controller_name == "home" && action_name == "index"
  end

  def self.noindex?(controller_name:, action_name:)
    !page_indexable?(controller_name:, action_name:)
  end

  def self.robots_txt_body
    if production?
      <<~ROBOTS.strip
        User-agent: *
        Disallow: /
        Allow: /$
      ROBOTS
    else
      <<~ROBOTS.strip
        User-agent: *
        Disallow: /
      ROBOTS
    end
  end
end
