# frozen_string_literal: true

class SessionsController < Devise::SessionsController
  layout :layout_for_devise

  prepend_before_action :clear_legacy_host_only_auth_cookies, only: [:new, :create, :destroy]
  before_action :prevent_auth_page_caching, only: [:new, :create]

  def create
    super do |user|
      if user.persisted?
        PostHog.identify(distinct_id: user.posthog_distinct_id, properties: user.posthog_properties)
        PostHog.capture(distinct_id: user.posthog_distinct_id, event: 'web_login', properties: { login_method: 'web' })
      end
    end
  end

  def destroy
    super
  ensure
    SessionCookieDomain.clear_all_auth_cookies(cookies)
  end

  private

  def clear_legacy_host_only_auth_cookies
    SessionCookieDomain.clear_host_only_auth_cookies(cookies)
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
