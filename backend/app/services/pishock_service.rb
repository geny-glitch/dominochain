# frozen_string_literal: true

require "cgi"
require "net/http"
require "json"
require "uri"

# PiShock Public API v1 (OpenAPI): https://api.pishock.com/swagger/index.html
# Operate: POST /Shockers/{ShockerId} with X-PiShock-Api-Key + X-PiShock-Username.
class PishockService
  API_BASE = "https://api.pishock.com"
  APP_NAME = "BG_showcase"
  USER_AGENT = "#{APP_NAME}/1.0"

  class << self
    def shock!(user:, intensity:, duration:)
      new(user).shock(intensity: intensity, duration: duration)
    end

    def test_connection!(user:)
      new(user).test_connection
    end
  end

  def initialize(user)
    @user = user
  end

  # Returns :ok, :skipped, :auth_error, :device_error, or :error
  def shock(intensity:, duration:)
    return :skipped unless @user.pishock_enabled?
    return :skipped unless BetaCatalog.new(@user).action_enabled?("pishock")
    return :skipped unless credentials_complete?

    intensity = intensity.to_i.clamp(1, 100)
    duration_ms = duration_to_milliseconds(duration)

    shocker_id = resolve_shocker_id!
    return :error if shocker_id.blank?

    operate!(
      shocker_id,
      operation: 0,
      duration_ms: duration_ms,
      intensity: intensity
    )
  end

  def test_connection
    return :skipped unless credentials_complete?

    case verify_api_credentials
    when :auth_error then return :auth_error
    when :error then return :error
    end

    shocker_id = resolve_shocker_id!
    return :device_error if shocker_id.blank?

    case operate!(shocker_id, operation: 2, duration_ms: 1000, intensity: nil)
    when :ok then :ok
    when :device_error then :device_error
    else :error
    end
  end

  private

  def verify_api_credentials
    res, = http_get("/Account")
    return :ok if res.is_a?(Net::HTTPSuccess)
    return :auth_error if %w[401 403].include?(res.code)

    Rails.logger.warn("[PishockService] GET /Account status=#{res.code}")
    :error
  rescue StandardError => e
    Rails.logger.warn("[PishockService] GET /Account error=#{e.class}: #{e.message}")
    :error
  end

  # Resolves shocker id for POST /Shockers/{ShockerId}: match share code in GET /Share/GetShared,
  # or PUT /Share to claim codes, or a single owned shocker from GET /Shockers.
  def resolve_shocker_id!
    code = normalized_share_code
    return nil if code.blank?

    id = shocker_id_from_shared_list(code)
    return id if id.present?

    case claim_share_code!(code)
    when :not_found, :error
      return nil
    end

    id = shocker_id_from_shared_list(code)
    return id if id.present?

    fallback_single_owned_shocker_id
  end

  def shocker_id_from_shared_list(code)
    get_shared_list.each do |entry|
      next if entry["ShareCode"].blank?

      return entry["Id"].to_s if share_codes_equal?(entry["ShareCode"], code)
    end
    nil
  end

  def fallback_single_owned_shocker_id
    list = get_shockers_list
    return list.first["ShockerId"].to_s if list.size == 1

    nil
  end

  def get_shared_list
    res, body = http_get("/Share/GetShared")
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[PishockService] GET /Share/GetShared status=#{res.code} body=#{body.truncate(200)}")
      return []
    end

    data = JSON.parse(body)
    data.is_a?(Array) ? data : []
  rescue JSON::ParserError => e
    Rails.logger.warn("[PishockService] GET /Share/GetShared JSON error=#{e.message}")
    []
  end

  def claim_share_code!(code)
    res, body = http_put("/Share", { "Shares" => [code] })
    return :ok if res.is_a?(Net::HTTPSuccess)

    case res.code
    when "404"
      Rails.logger.warn("[PishockService] PUT /Share 404 — share code inconnu ou invalide. body=#{body.truncate(200)}")
      :not_found
    when "410"
      # "A Share is already claimed" — peut être une autre clé API ; on tentera GET /Shockers ensuite.
      Rails.logger.warn("[PishockService] PUT /Share 410 — code déjà revendiqué ailleurs ? body=#{body.truncate(200)}")
      :ok
    else
      Rails.logger.warn("[PishockService] PUT /Share status=#{res.code} body=#{body.truncate(200)}")
      :error
    end
  end

  def get_shockers_list
    res, body = http_get("/Shockers")
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[PishockService] GET /Shockers status=#{res.code} body=#{body.truncate(200)}")
      return []
    end

    data = JSON.parse(body)
    data.is_a?(Array) ? data : []
  rescue JSON::ParserError => e
    Rails.logger.warn("[PishockService] GET /Shockers JSON error=#{e.message}")
    []
  end

  # operation: 0 shock, 1 vibrate, 2 beep — Duration in milliseconds per OpenAPI.
  def operate!(shocker_id, operation:, duration_ms:, intensity:)
    payload = {
      "AgentName" => APP_NAME,
      "Operation" => operation,
      "Duration" => duration_ms
    }
    payload["Intensity"] = intensity unless intensity.nil?

    res, body = http_post("/Shockers/#{CGI.escapeURIComponent(shocker_id.to_s)}", payload)
    return :ok if res.is_a?(Net::HTTPSuccess)

    log_operate_failure(res, body)
    return :device_error if %w[404 405 503].include?(res.code)

    :error
  rescue StandardError => e
    Rails.logger.warn("[PishockService] operate error=#{e.class}: #{e.message}")
    :error
  end

  def duration_to_milliseconds(duration)
    if duration.is_a?(Float) && !duration.integer?
      raise ArgumentError, "PiShock: duration décimale doit être entre 0.1 et 1.5 s" unless (0.1...1.6).cover?(duration)

      (duration * 1000).to_i
    else
      duration.to_i.clamp(1, 15) * 1000
    end
  end

  def api_headers(json: false)
    h = {
      "X-PiShock-Api-Key" => @user.pishock_api_key.to_s.strip,
      "X-PiShock-Username" => @user.pishock_username.to_s.strip,
      "Accept" => "application/json",
      "User-Agent" => USER_AGENT
    }
    h["Content-Type"] = "application/json; charset=utf-8" if json
    h
  end

  def http_get(path)
    uri = URI("#{API_BASE}#{path}")
    req = Net::HTTP::Get.new(uri)
    api_headers(json: false).each { |k, v| req[k] = v }
    perform(uri, req)
  end

  def http_put(path, data)
    uri = URI("#{API_BASE}#{path}")
    req = Net::HTTP::Put.new(uri)
    api_headers(json: true).each { |k, v| req[k] = v }
    req.body = JSON.generate(data)
    perform(uri, req)
  end

  def http_post(path, data)
    uri = URI("#{API_BASE}#{path}")
    req = Net::HTTP::Post.new(uri)
    api_headers(json: true).each { |k, v| req[k] = v }
    req.body = JSON.generate(data)
    perform(uri, req)
  end

  def perform(uri, req)
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 20, open_timeout: 10) do |http|
      http.request(req)
    end
    [res, res.body.to_s]
  end

  def log_operate_failure(res, body)
    hint =
      case res.code
      when "404"
        " (share / shocker introuvable pour cette clé)"
      when "405"
        " (opération interdite par le share, ex. shock désactivé)"
      when "503"
        " (share ou shocker en pause / indisponible)"
      when "412"
        " (intensité hors limites)"
      when "416"
        " (durée hors limites, API en ms : 16–15000)"
      else
        ""
      end
    snippet = body.present? ? body.truncate(300) : "(vide)"
    Rails.logger.warn("[PishockService] POST /Shockers status=#{res.code} body=#{snippet}#{hint}")
  end

  def normalized_share_code
    @user.pishock_share_code.to_s.strip.delete(" \t\r\n")
  end

  def share_codes_equal?(a, b)
    a.to_s.strip.casecmp?(b.to_s.strip)
  end

  def credentials_complete?
    @user.pishock_username.to_s.strip.present? &&
      @user.pishock_api_key.to_s.strip.present? &&
      normalized_share_code.present?
  end
end
