# frozen_string_literal: true

class SessionsController < Devise::SessionsController
  layout :layout_for_devise

  def create
    super do |user|
      if user.persisted?
        PostHog.identify(distinct_id: user.posthog_distinct_id, properties: user.posthog_properties)
        PostHog.capture(distinct_id: user.posthog_distinct_id, event: 'web_login', properties: { login_method: 'web' })
      end
    end
  end

  private

  def layout_for_devise
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
