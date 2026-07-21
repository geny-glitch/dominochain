# frozen_string_literal: true

# Use host-only session cookies. Setting Domain=.dominochain.app on the session
# cookie broke CSRF verification on POST /login in production (every form submit
# returned 422 InvalidAuthenticityToken).
Rails.application.config.session_store :cookie_store,
  key: "_backend_session",
  secure: Rails.env.production?,
  same_site: :lax
