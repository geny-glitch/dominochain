# frozen_string_literal: true

class WikimediaCommonsService
  API_URL = "https://commons.wikimedia.org/w/api.php".freeze
  IMAGES_PER_STAR = 10

  class << self
    def fetch_and_store_for_name(name)
      return [] if name.blank?
      name = name.strip
      urls = fetch_image_urls_from_api(name, IMAGES_PER_STAR)
      saved = []
      urls.each do |url|
        img = InfluencerImage.find_or_initialize_by(url: url)
        img.name = name
        img.source = "wikimedia"
        if img.save
          saved << img
        end
      end
      saved
    end

    def fetch_and_store_all
      names = AppSetting.instance.influencer_names_list
      total = 0
      names.each do |name|
        count = fetch_and_store_for_name(name).size
        total += count
        sleep 0.3 # Be nice to the API
      end
      total
    end

    def fetch_image_urls_from_api(search_term, limit = 10)
      uri = URI(API_URL)
      uri.query = URI.encode_www_form(
        action: "query",
        generator: "search",
        gsrsearch: search_term,
        gsrnamespace: 6,
        gsrlimit: limit,
        prop: "imageinfo",
        iiprop: "url",
        iiurlwidth: 400,
        format: "json"
      )

      response = Net::HTTP.get_response(uri)
      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      pages = data.dig("query", "pages")
      return [] unless pages

      pages.values.filter_map do |page|
        imageinfo = page.dig("imageinfo", 0)
        imageinfo&.dig("thumburl") || imageinfo&.dig("url")
      end
    rescue StandardError => e
      Rails.logger.warn "[Wikimedia] Failed to fetch #{search_term}: #{e.message}"
      []
    end
  end
end
