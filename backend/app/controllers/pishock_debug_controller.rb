# frozen_string_literal: true

# Step-by-step PiShock API checks (auth + ps.pishock.com) per official docs:
# https://docs.pishock.com/pishock/api-documentation/pishock-api-documentation.html
class PishockDebugController < ApplicationController
  # Legacy: full blob used to live in the session cookie → 4KB overflow.
  SESSION_KEY = "pishock_debug_session_v1"
  SESSION_REF_KEY = "pishock_debug_ref_v2"
  SESSION_FALLBACK_KEY = "pishock_debug_fb_v1"
  CACHE_KEY_PREFIX = "pishock_debug/v2"
  CACHE_TTL = 2.hours

  USER_AGENT = "BG_pishock_debug/1.0"
  # With a real cache store, previews can be large; cookie fallback (dev without caching) stays tiny.
  LOG_BODY_PREVIEW_CHARS = 12_000
  LOGS_MAX = 12
  SESSION_PREVIEW_CHARS = 600
  SESSION_LOGS_MAX = 3

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :drop_legacy_session_blob!

  def show
    clear_session if params[:reset].present?
    load_session
  end

  def step1
    username = debug_params[:username].to_s.strip
    apikey = debug_params[:apikey].to_s.strip
    if username.blank? || apikey.blank?
      redirect_to beta_pishock_debug_path, alert: "Renseigne le nom d’utilisateur et la clé API."
      return
    end

    merge_ctx("username" => username, "apikey" => apikey)
    uri_base = "https://auth.pishock.com/Auth/GetUserIfAPIKeyValid"
    res = http_get(uri_base, { "apikey" => apikey, "username" => username })
    uid = parse_user_id(res[:body])
    merge_ctx("user_id" => uid.to_s) if uid.present?

    append_log(
      step: 1,
      title: "1. GetUserIfAPIKeyValid",
      doc: "GET https://auth.pishock.com/Auth/GetUserIfAPIKeyValid?apikey=…&username=…",
      request_summary: "#{uri_base}?username=#{ERB::Util.url_encode(username)}&apikey=[MASQUÉ]",
      **res
    )

    redirect_to beta_pishock_debug_path, notice: "Étape 1 exécutée."
  end

  def step2
    unless debug_ctx_ready?(:username, :apikey, :user_id)
      redirect_to beta_pishock_debug_path, alert: "Fais d’abord l’étape 1 (UserId manquant)."
      return
    end

    ctx = read_debug_data["ctx"]
    path = "/PiShock/GetUserDevices"
    query = { "UserId" => ctx["user_id"].to_s, "Token" => ctx["apikey"], "api" => "true" }
    res = http_get("https://ps.pishock.com#{path}", query)

    append_log(
      step: 2,
      title: "2. GetUserDevices (UserID + API Key)",
      doc: "GET https://ps.pishock.com/PiShock/GetUserDevices?UserId=…&Token={apikey}&api=true",
      request_summary: "GET https://ps.pishock.com#{path}?UserId=#{ctx['user_id']}&Token=[MASQUÉ]&api=true",
      **res
    )

    redirect_to beta_pishock_debug_path, notice: "Étape 2 exécutée."
  end

  def step3
    unless debug_ctx_ready?(:username, :apikey, :user_id)
      redirect_to beta_pishock_debug_path, alert: "Fais d’abord l’étape 1 (UserId manquant)."
      return
    end

    ctx = read_debug_data["ctx"]
    path = "/PiShock/GetShareCodesByOwner"
    query = { "UserId" => ctx["user_id"].to_s, "Token" => ctx["apikey"], "api" => "true" }
    res = http_get("https://ps.pishock.com#{path}", query)

    append_log(
      step: 3,
      title: "3. GetShareCodesByOwner",
      doc: "GET https://ps.pishock.com/PiShock/GetShareCodesByOwner?UserId=…&Token={apikey}&api=true",
      request_summary: "GET https://ps.pishock.com#{path}?UserId=#{ctx['user_id']}&Token=[MASQUÉ]&api=true",
      **res
    )

    redirect_to beta_pishock_debug_path, notice: "Étape 3 exécutée."
  end

  def step4
    unless debug_ctx_ready?(:username, :apikey, :user_id)
      redirect_to beta_pishock_debug_path, alert: "Fais d’abord l’étape 1 (UserId manquant)."
      return
    end

    raw_ids = debug_params[:share_ids].to_s.split(/[\s,]+/).map(&:strip).reject(&:blank?)
    if raw_ids.empty?
      redirect_to beta_pishock_debug_path, alert: "Indique au moins un shareId (nombres séparés par des virgules)."
      return
    end

    ctx = read_debug_data["ctx"]
    path = "/PiShock/GetShockersByShareIds"
    pairs = [
      ["UserId", ctx["user_id"].to_s],
      ["Token", ctx["apikey"]],
      ["api", "true"]
    ]
    raw_ids.each { |id| pairs << ["shareIds", id] }
    uri = URI("https://ps.pishock.com#{path}")
    uri.query = URI.encode_www_form(pairs)
    res = http_get_uri(uri)

    append_log(
      step: 4,
      title: "4. GetShockersByShareIds",
      doc: "GET https://ps.pishock.com/PiShock/GetShockersByShareIds?UserId=…&Token=…&api=true&shareIds=… (répéter shareIds)",
      request_summary: "GET #{uri.scheme}://#{uri.host}#{uri.path}?UserId=#{ctx['user_id']}&Token=[MASQUÉ]&api=true&shareIds=#{raw_ids.join(',')}",
      **res
    )

    redirect_to beta_pishock_debug_path, notice: "Étape 4 exécutée."
  end

  def clear
    clear_session
    redirect_to beta_pishock_debug_path, notice: "Session de debug effacée."
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: "Accès réservé aux betas."
  end

  def debug_params
    params.fetch(:pishock_debug, {}).permit(:username, :apikey, :share_ids)
  end

  def load_session
    data = read_debug_data
    @ctx = data["ctx"]
    @logs = data["logs"].last(logs_cap)
    @prefill_username = @ctx["username"].presence || current_user.pishock_username
    @pishock_debug_cookie_limited = !cache_usable?
  end

  def merge_ctx(attrs)
    data = read_debug_data
    data["ctx"].merge!(attrs.stringify_keys.compact)
    write_debug_data(data)
  end

  def append_log(**entry)
    data = read_debug_data
    body = entry[:body] || entry["body"]
    row = entry.except(:body, "body").stringify_keys
    row["body_preview"] = format_body(body).truncate(log_preview_cap, omission: "… [tronqué]")
    row["doc"] = row["doc"].to_s.truncate(400, omission: "…")
    row["request_summary"] = row["request_summary"].to_s.truncate(400, omission: "…")
    row["at"] = Time.current.iso8601
    data["logs"] << row
    data["logs"] = data["logs"].last(logs_cap)
    write_debug_data(data)
  end

  def clear_session
    ref = session[SESSION_REF_KEY]
    Rails.cache.delete(debug_cache_key_for(current_user.id, ref)) if ref.present? && cache_usable?
    session.delete(SESSION_REF_KEY)
    session.delete(SESSION_KEY)
    session.delete(SESSION_FALLBACK_KEY)
  end

  def debug_ctx_ready?(*keys)
    ctx = read_debug_data["ctx"]
    keys.all? { |k| ctx[k.to_s].present? }
  end

  def drop_legacy_session_blob!
    session.delete(SESSION_KEY)
  end

  def cache_usable?
    !Rails.cache.instance_of?(ActiveSupport::Cache::NullStore)
  end

  def ensure_debug_ref!
    return unless cache_usable?

    session[SESSION_REF_KEY] ||= SecureRandom.hex(16)
  end

  def read_debug_data
    if cache_usable?
      ensure_debug_ref!
      Rails.cache.read(debug_cache_key) || empty_debug_data
    else
      session[SESSION_FALLBACK_KEY] || empty_debug_data
    end
  end

  def write_debug_data(data)
    if cache_usable?
      ensure_debug_ref!
      Rails.cache.write(debug_cache_key, data, expires_in: CACHE_TTL)
    else
      shrink_debug_data_for_cookie!(data)
      session[SESSION_FALLBACK_KEY] = data
    end
  end

  def empty_debug_data
    { "ctx" => {}, "logs" => [] }
  end

  def shrink_debug_data_for_cookie!(data)
    data["logs"] = data["logs"].last(SESSION_LOGS_MAX).map do |row|
      row.merge(
        "body_preview" => row["body_preview"].to_s.truncate(SESSION_PREVIEW_CHARS, omission: "…"),
        "doc" => row["doc"].to_s.truncate(250, omission: "…"),
        "request_summary" => row["request_summary"].to_s.truncate(250, omission: "…")
      )
    end
  end

  def logs_cap
    cache_usable? ? LOGS_MAX : SESSION_LOGS_MAX
  end

  def log_preview_cap
    cache_usable? ? LOG_BODY_PREVIEW_CHARS : SESSION_PREVIEW_CHARS
  end

  def debug_cache_key
    debug_cache_key_for(current_user.id, session[SESSION_REF_KEY])
  end

  def debug_cache_key_for(user_id, ref)
    "#{CACHE_KEY_PREFIX}/#{user_id}/#{ref}"
  end

  def http_get(base_url, query_hash)
    uri = URI(base_url)
    uri.query = URI.encode_www_form(query_hash)
    http_get_uri(uri)
  end

  def http_get_uri(uri)
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "application/json, text/plain, */*"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 25, open_timeout: 10) do |http|
      http.request(req)
    end

    {
      http_status: res.code.to_i,
      http_success: res.is_a?(Net::HTTPSuccess),
      body: res.body.to_s
    }
  end

  def format_body(body)
    return "" if body.blank?

    JSON.pretty_generate(JSON.parse(body))
  rescue JSON::ParserError
    body.truncate(2000)
  end

  def parse_user_id(body)
    return nil if body.blank?

    data = JSON.parse(body)
    case data
    when Hash
      data["UserId"] || data["UserID"] || data["userId"] || data["user_id"]
    end
  rescue JSON::ParserError
    nil
  end
end
