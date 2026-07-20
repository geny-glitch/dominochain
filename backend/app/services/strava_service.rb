# frozen_string_literal: true

class StravaService
  AUTH_URL = "https://www.strava.com/oauth/authorize"
  TOKEN_URL = "https://www.strava.com/oauth/token"
  API_BASE = "https://www.strava.com/api/v3"
  SCOPES = %w[read activity:read_all].freeze
  ACTIVITIES_PER_PAGE = 100

  class Error < StandardError; end
  class Unauthorized < Error; end
  class IntegrationUnavailable < Error; end

  def initialize(user)
    @user = user
  end

  def self.authorization_url(redirect_uri:, state:)
    params = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      approval_prompt: "auto",
      scope: SCOPES.join(","),
      state: state
    }
    "#{AUTH_URL}?#{params.to_query}"
  end

  def self.exchange_code_for_tokens(code:)
    raise Error, "STRAVA_CLIENT_ID ou STRAVA_CLIENT_SECRET manquants" unless configured?

    body = token_request(
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code"
    )

    token_payload(body)
  end

  def refresh_tokens!
    raise Error, "Aucun refresh token Strava" unless @user.strava_refresh_token.present?
    raise Error, "STRAVA_CLIENT_ID ou STRAVA_CLIENT_SECRET manquants" unless self.class.configured?

    body = self.class.token_request(
      client_id: self.class.client_id,
      client_secret: self.class.client_secret,
      refresh_token: @user.strava_refresh_token,
      grant_type: "refresh_token"
    )

    payload = self.class.token_payload(body)
    @user.update!(
      strava_access_token: payload[:access_token],
      strava_refresh_token: payload[:refresh_token] || @user.strava_refresh_token,
      strava_token_expires_at: payload[:expires_at],
      strava_athlete_id: payload[:athlete_id] || @user.strava_athlete_id
    )
  end

  def ensure_valid_token!
    raise Unauthorized, "Strava non connecté" unless @user.strava_access_token.present?

    if @user.strava_token_expires_at.present? && @user.strava_token_expires_at < 1.minute.from_now
      refresh_tokens!
    end
  end

  def activities_between(start_time:, end_time:, include_details: false)
    ensure_valid_token!

    activities = []
    page = 1

    loop do
      batch = get_json(
        "/athlete/activities",
        after: start_time.to_i,
        before: end_time.to_i,
        per_page: ACTIVITIES_PER_PAGE,
        page: page
      )
      batch = Array(batch)
      activities.concat(batch)
      break if batch.length < ACTIVITIES_PER_PAGE

      page += 1
    end

    activities = activities.map do |activity|
      if include_details && activity["id"].present?
        activity.merge(activity(activity["id"]))
      else
        activity
      end
    end

    activities.map { |activity| normalize_activity(activity) }
  end

  def activity(activity_id)
    ensure_valid_token!
    get_json("/activities/#{activity_id}")
  end

  def disconnect!
    @user.strava_goals.update_all(enabled: false, updated_at: Time.current)
    @user.update!(
      strava_access_token: nil,
      strava_refresh_token: nil,
      strava_token_expires_at: nil,
      strava_athlete_id: nil
    )
  end

  def self.client_id
    ENV["STRAVA_CLIENT_ID"]
  end

  def self.client_secret
    ENV["STRAVA_CLIENT_SECRET"]
  end

  def self.configured?
    client_id.present? && client_secret.present?
  end

  def self.token_request(params)
    uri = URI(TOKEN_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.set_form_data(params)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    body = JSON.parse(res.body.presence || "{}")

    raise Error, body["message"] || body["error"] || "Échec token Strava" unless res.is_a?(Net::HTTPSuccess)

    body
  end

  def self.token_payload(body)
    {
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      expires_at: body["expires_at"].present? ? Time.zone.at(body["expires_at"].to_i) : nil,
      athlete_id: body.dig("athlete", "id")&.to_s
    }
  end

  private

  def normalize_activity(activity)
    device_parts = [
      activity["device_name"],
      activity.dig("gear", "name")
    ].compact_blank

    {
      id: activity["id"],
      name: activity["name"],
      type: activity["type"],
      sport_type: activity["sport_type"],
      duration_seconds: (activity["moving_time"] || activity["elapsed_time"]).to_i,
      calories: activity["calories"]&.to_i,
      device_name: device_parts.join(" / "),
      started_at: parse_time(activity["start_date"])
    }
  end

  def parse_time(value)
    value.present? ? Time.zone.parse(value) : nil
  rescue ArgumentError, TypeError
    nil
  end

  def get_json(path, **query)
    retried_auth = query.delete(:retried_auth) || false
    uri = URI("#{API_BASE}#{path}")
    uri.query = URI.encode_www_form(query.compact) if query.present?

    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{@user.reload.strava_access_token}"
    req["Content-Type"] = "application/json"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.code == "401" && !retried_auth
      refresh_tokens!
      return get_json(path, **query, retried_auth: true)
    end

    body = JSON.parse(res.body.presence || "{}")
    raise api_error_for(body, res.code) if res.code == "403" || res.code == "401"
    raise Error, body["message"] || "Erreur Strava #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    body
  end

  def api_error_for(body, status_code)
    if inactive_application?(body)
      raise IntegrationUnavailable, body["message"].presence || "Strava integration unavailable"
    end

    raise Unauthorized, body["message"].presence || "Strava non autorisé" if status_code == "403" || status_code == "401"
  end

  def inactive_application?(body)
    Array(body["errors"]).any? do |error|
      error["resource"].to_s == "Application" && error["code"].to_s == "Inactive"
    end
  end
end
