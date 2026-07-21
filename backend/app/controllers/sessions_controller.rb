# frozen_string_literal: true

class SessionsController < Devise::SessionsController
  layout :layout_for_devise

  before_action :clear_legacy_shared_domain_auth_cookies, only: [:new, :destroy]
  before_action :prevent_auth_page_caching, only: [:new, :create]

  def create
    super do |user|
      if user.persisted?
        PostHog.identify(distinct_id: user.posthog_distinct_id, properties: user.posthog_properties)
        PostHog.capture(distinct_id: user.posthog_distinct_id, event: 'web_login', properties: { login_method: 'web' })
      end
    end
  end

  private

  LEGACY_SHARED_COOKIE_DOMAIN = ".dominochain.app"
  LEGACY_AUTH_COOKIE_KEYS = %w[_backend_session remember_user_token].freeze

  def clear_legacy_shared_domain_auth_cookies
    return unless Rails.env.production?

    LEGACY_AUTH_COOKIE_KEYS.each do |key|
      cookies.delete(key, domain: LEGACY_SHARED_COOKIE_DOMAIN, secure: true, same_site: :lax)
    end
  end

  def prevent_auth_page_caching
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
  end

  def layout_for_devise
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
