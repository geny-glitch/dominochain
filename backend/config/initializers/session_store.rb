# frozen_string_literal: true

# Share the session cookie across app subdomains in production (e.g.
# dominochain.app and beta.dominochain.app). Host-only cookies caused
# apparent logouts when navigation crossed subdomains.
module SessionCookieDomain
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
end

Rails.application.config.session_store :cookie_store,
  key: "_backend_session",
  secure: Rails.env.production?,
  same_site: :lax,
  domain: SessionCookieDomain.for_environment
