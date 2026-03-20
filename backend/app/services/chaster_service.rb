# frozen_string_literal: true

class ChasterService
  AUTH_URL = "https://sso.chaster.app/auth/realms/app/protocol/openid-connect/auth"
  TOKEN_URL = "https://sso.chaster.app/auth/realms/app/protocol/openid-connect/token"
  API_BASE = "https://api.chaster.app"

  SCOPES = %w[profile locks].freeze

  class Error < StandardError; end
  class TokenExpired < Error; end
  class Unauthorized < Error; end

  def initialize(user)
    @user = user
  end

  def self.authorization_url(redirect_uri:, state:)
    params = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: SCOPES.join(" "),
      state: state
    }
    "#{AUTH_URL}?#{params.to_query}"
  end

  def self.exchange_code_for_tokens(code:, redirect_uri:)
    raise Error, "CHASTER_CLIENT_ID ou CHASTER_CLIENT_SECRET manquants" unless client_id.present? && client_secret.present?

    uri = URI(TOKEN_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.set_form_data(
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri
    )

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    body = JSON.parse(res.body)

    raise Error, body["error_description"] || body["error"] || "Échec échange token" unless res.is_a?(Net::HTTPSuccess)

    {
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      expires_in: body["expires_in"]&.to_i
    }
  end

  def refresh_tokens!
    raise Error, "Aucun refresh token" unless @user.chaster_refresh_token.present?
    raise Error, "CHASTER_CLIENT_ID ou CHASTER_CLIENT_SECRET manquants" unless self.class.client_id.present? && self.class.client_secret.present?

    uri = URI(TOKEN_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.set_form_data(
      client_id: self.class.client_id,
      client_secret: self.class.client_secret,
      grant_type: "refresh_token",
      refresh_token: @user.chaster_refresh_token
    )

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    body = JSON.parse(res.body)

    raise Error, body["error_description"] || body["error"] || "Échec refresh token" unless res.is_a?(Net::HTTPSuccess)

    expires_at = body["expires_in"].present? ? Time.current + body["expires_in"].to_i.seconds : nil
    @user.update!(
      chaster_access_token: body["access_token"],
      chaster_refresh_token: body["refresh_token"] || @user.chaster_refresh_token,
      chaster_token_expires_at: expires_at
    )
  end

  def ensure_valid_token!
    return unless @user.chaster_access_token.present?

    if @user.chaster_token_expires_at.present? && @user.chaster_token_expires_at < 1.minute.from_now
      refresh_tokens!
    end
  end

  def fetch_locks(status: "active")
    ensure_valid_token!
    raise Unauthorized, "Chaster non connecté" unless @user.chaster_access_token.present?

    uri = URI("#{API_BASE}/locks")
    uri.query = URI.encode_www_form(status: status)

    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{@user.chaster_access_token}"
    req["Content-Type"] = "application/json"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.code == "401"
      refresh_tokens!
      return fetch_locks(status: status) # retry once
    end

    raise Unauthorized, "Chaster non autorisé" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  CACHE_TTL = 2.minutes

  def current_lock
    ensure_valid_token!
    raise Unauthorized, "Chaster non connecté" unless @user.chaster_access_token.present?

    # Utiliser le cache DB si frais
    cached = current_lock_from_db
    return cached if cached.present?

    # Sinon fetch Chaster, sync DB, retourner
    sync_locks!
    current_lock_from_db
  end

  def sync_locks!
    locks = fetch_locks
    locks = Array(locks)
    active_ids = locks.filter_map { |l| l["_id"] if (l["status"] || l["Status"]) == "locked" }

    # Marquer comme terminés les locks qu'on avait en "locked" mais qui ne sont plus actifs
    @user.chaster_locks.active.where.not(chaster_lock_id: active_ids).find_each do |lock|
      lock.update!(status: "unlocked", unlocked_at: Time.current)
    end

    # Upsert les locks actifs
    locks.each do |lock_data|
      next unless (lock_data["status"] || lock_data["Status"]) == "locked"

      upsert_lock(lock_data)
    end
  end

  def current_lock_from_db
    lock = @user.chaster_locks.active.recent.first
    return nil unless lock
    return nil if lock.updated_at < CACHE_TTL.ago

    build_lock_info_from_record(lock)
  end

  def self.client_id
    ENV["CHASTER_CLIENT_ID"]
  end

  def self.client_secret
    ENV["CHASTER_CLIENT_SECRET"]
  end

  def self.configured?
    client_id.present? && client_secret.present?
  end

  def add_time_to_lock(lock_id, seconds)
    ensure_valid_token!
    raise Unauthorized, "Chaster non connecté" unless @user.chaster_access_token.present?

    uri = URI("#{API_BASE}/locks/#{lock_id}/update-time")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@user.chaster_access_token}"
    req["Content-Type"] = "application/json"
    req.body = { duration: seconds }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.code == "401"
      refresh_tokens!
      return add_time_to_lock(lock_id, seconds)
    end

    raise Error, "Chaster: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    # Invalider le cache pour forcer un refresh
    @user.chaster_locks.where(chaster_lock_id: lock_id).update_all(updated_at: 2.hours.ago)
  end

  private

  def upsert_lock(lock_data)
    end_date_str = lock_data["endDate"]
    end_date = end_date_str.present? ? Time.zone.parse(end_date_str) : nil

    lock = @user.chaster_locks.find_or_initialize_by(chaster_lock_id: lock_data["_id"])
    lock.assign_attributes(
      title: lock_data["title"],
      status: "locked",
      start_date: lock_data["startDate"].present? ? Time.zone.parse(lock_data["startDate"]) : nil,
      end_date: end_date,
      is_frozen: lock_data["isFrozen"] == true,
      frozen_at: lock_data["frozenAt"].present? ? Time.zone.parse(lock_data["frozenAt"]) : nil,
      total_duration: lock_data["totalDuration"]&.to_i,
      raw_data: lock_data.except("combination")
    )
    lock.save!
  end

  def build_lock_info_from_record(lock)
    remaining_seconds = if lock.is_frozen
                          nil
                        elsif lock.end_date
                          [lock.end_date - Time.current, 0].max.to_i
                        else
                          nil
                        end

    {
      id: lock.chaster_lock_id,
      title: lock.title,
      end_date: lock.end_date&.iso8601,
      is_frozen: lock.is_frozen,
      remaining_seconds: remaining_seconds,
      display_remaining_time: true
    }
  end

  def build_lock_info(lock)
    # Chaster API uses camelCase
    end_date_str = lock["endDate"]
    is_frozen = lock["isFrozen"] == true

    end_date = end_date_str.present? ? Time.zone.parse(end_date_str) : nil

    remaining_seconds = if is_frozen
                          nil # temps gelé, pas de compte à rebours
                        elsif end_date
                          [end_date - Time.current, 0].max.to_i
                        else
                          nil
                        end

    {
      id: lock["_id"],
      title: lock["title"],
      end_date: end_date&.iso8601,
      is_frozen: is_frozen,
      remaining_seconds: remaining_seconds,
      display_remaining_time: lock["displayRemainingTime"] != false
    }
  end
end
