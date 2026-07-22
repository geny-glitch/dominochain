# frozen_string_literal: true

require "net/http"
require "json"

class ChessComService
  API_BASE = "https://api.chess.com/pub"
  USER_AGENT = "DominoChain-Beta/1.0 (contact: lucas@dominochain.app)"
  VERIFICATION_CODE_TTL = 24.hours
  RATING_TYPE_TO_STATS_KEY = {
    "blitz" => "chess_blitz",
    "bullet" => "chess_bullet",
    "rapid" => "chess_rapid",
    "daily" => "chess_daily"
  }.freeze

  class Error < StandardError; end
  class NotFound < Error; end
  class NotVerified < Error; end
  class RatingUnavailable < Error; end

  def initialize(user = nil)
    @user = user
  end

  def self.normalize_username(username)
    username.to_s.strip.downcase.gsub(/\s+/, "")
  end

  def self.generate_verification_code
    "BG-#{SecureRandom.alphanumeric(6).upcase}"
  end

  def self.current_rating(stats, rating_type)
    key = RATING_TYPE_TO_STATS_KEY[rating_type.to_s]
    raise Error, "Unknown rating type: #{rating_type}" if key.blank?

    rating = stats.dig(key, "last", "rating") || stats.dig(key.to_sym, :last, :rating)
    rating&.to_i
  end

  def self.ratings_summary(stats)
    ChessComGoal::RATING_TYPES.index_with do |type|
      current_rating(stats, type)
    end
  end

  def fetch_profile(username)
    username = self.class.normalize_username(username)
    raise Error, "Username blank" if username.blank?

    get_json("/player/#{CGI.escape(username)}")
  end

  def fetch_stats(username)
    username = self.class.normalize_username(username)
    raise Error, "Username blank" if username.blank?

    get_json("/player/#{CGI.escape(username)}/stats")
  end

  def verify_location!(username, code)
    profile = fetch_profile(username)
    location = profile["location"].to_s
    raise Error, "Verification code missing from profile location" if code.blank?
    unless location.downcase.include?(code.to_s.downcase)
      raise Error, "Verification code not found in Chess.com location"
    end

    profile
  end

  def current_rating_for!(username, rating_type)
    stats = fetch_stats(username)
    rating = self.class.current_rating(stats, rating_type)
    if rating.blank? || rating <= 0
      raise RatingUnavailable, "No #{rating_type} rating available for #{username}"
    end

    rating
  end

  private

  def get_json(path)
    uri = URI("#{API_BASE}#{path}")
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "application/json"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
      http.request(req)
    end

    case
    when res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    when res.is_a?(Net::HTTPNotFound)
      raise NotFound, "Chess.com player not found"
    else
      raise Error, "Chess.com API error: #{res.code}"
    end
  rescue JSON::ParserError => e
    raise Error, "Invalid Chess.com API response: #{e.message}"
  end
end
