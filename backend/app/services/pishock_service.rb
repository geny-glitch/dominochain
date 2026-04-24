# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class PishockService
  # Same path as official Python client (pishock.zap.httpapi).
  API_URL = "https://do.pishock.com/api/apioperate"
  APP_NAME = "BG_showcase"
  USER_AGENT = "#{APP_NAME}/1.0"

  class << self
    def shock!(user:, intensity:, duration:)
      new(user).shock(intensity: intensity, duration: duration)
    end
  end

  def initialize(user)
    @user = user
  end

  # Returns :ok, :skipped (not configured), or :error
  def shock(intensity:, duration:)
    return :skipped unless @user.pishock_enabled?
    return :skipped unless credentials_complete?

    intensity = intensity.to_i.clamp(1, 100)
    duration_value = normalize_duration(duration)

    uri = URI(API_URL)
    # Integer JSON fields match python `requests.post(..., json=params)` (see pishock.zap.httpapi).
    payload = {
      "Username" => @user.pishock_username.to_s,
      "Apikey" => @user.pishock_api_key.to_s,
      "Code" => @user.pishock_share_code.to_s,
      "Name" => APP_NAME,
      "Op" => 0,
      "Intensity" => intensity,
      "Duration" => duration_value
    }

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json; charset=utf-8"
    req["User-Agent"] = USER_AGENT
    req.body = JSON.generate(payload)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
      http.request(req)
    end

    body = res.body.to_s.strip
    if res.is_a?(Net::HTTPSuccess) && body.include?("Operation Succeeded")
      :ok
    else
      log_failure(res, body)
      :error
    end
  rescue ArgumentError => e
    Rails.logger.warn("[PishockService] user_id=#{@user.id} error=#{e.message}")
    :error
  rescue StandardError => e
    Rails.logger.warn("[PishockService] user_id=#{@user.id} error=#{e.class}: #{e.message}")
    :error
  end

  private

  # PiShock accepts whole seconds 1–15, or sub-second floats as milliseconds (100–1500), same as Python-PiShock.
  def normalize_duration(duration)
    if duration.is_a?(Float) && !duration.integer?
      raise ArgumentError, "PiShock: duration décimale doit être entre 0.1 et 1.5 s" unless (0.1...1.6).cover?(duration)

      (duration * 1000).to_i
    else
      duration.to_i.clamp(1, 15)
    end
  end

  def log_failure(res, body)
    hint =
      if res.code == "404"
        " PiShock renvoie souvent HTTP 404 si le share code est invalide, révoqué, ou déjà « pris » par une autre session (voir logs sur pishock.com)."
      else
        ""
      end
    snippet = body.present? ? body.truncate(200) : "(vide)"
    Rails.logger.warn("[PishockService] user_id=#{@user.id} status=#{res.code} body=#{snippet}#{hint}")
  end

  def credentials_complete?
    @user.pishock_username.present? &&
      @user.pishock_api_key.present? &&
      @user.pishock_share_code.present?
  end
end
