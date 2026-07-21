# frozen_string_literal: true

# Share the session cookie across app subdomains in production (e.g.
# dominochain.app and beta.dominochain.app). Host-only cookies caused
# apparent logouts when navigation crossed subdomains.
module SessionCookieDomain
  SESSION_KEY = "_backend_session"
  REMEMBER_KEY = "remember_user_token"

  module_function

  def for_environment
    return nil unless Rails.env.production?

    host = URI.parse(ENV.fetch("APP_PUBLIC_BASE_URL", "https://dominochain.app")).host.to_s.downcase
    return nil if host.blank?
    return nil if host.in?(%w[localhost 127.0.0.1]) || host.end_with?(".fly.dev")

    segments = host.split(".")
    return nil if segments.length < 2

    ".#{segments.last(2).join(".")}"
  end

  def shared_cookie_options
    {
      secure: Rails.env.production?,
      same_site: :lax,
      domain: for_environment
    }.compact
  end

  # Before sharing sessions across subdomains, cookies were host-only. Browsers can
  # keep both variants; Rails may then read a stale session and reject the CSRF token.
  def clear_host_only_auth_cookies(cookies)
    return unless for_environment

    [SESSION_KEY, REMEMBER_KEY].each do |key|
      cookies.delete(key, secure: Rails.env.production?, same_site: :lax)
    end
  end

  def clear_all_auth_cookies(cookies)
    return unless for_environment

    shared_domain = for_environment
    [SESSION_KEY, REMEMBER_KEY].each do |key|
      cookies.delete(key, secure: Rails.env.production?, same_site: :lax)
      cookies.delete(key, secure: Rails.env.production?, same_site: :lax, domain: shared_domain)
    end
  end
end

Rails.application.config.session_store :cookie_store,
  key: SessionCookieDomain::SESSION_KEY,
  **SessionCookieDomain.shared_cookie_options

Rails.application.config.after_initialize do
  Devise.rememberable_options = SessionCookieDomain.shared_cookie_options
end
