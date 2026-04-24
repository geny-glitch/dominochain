# frozen_string_literal: true

# Logs outgoing HTTP client calls (Net::HTTP, OpenURI, …) in development only.
# https://github.com/trusche/httplog
if Rails.env.development?
  require "httplog"

  HttpLog.configure do |config|
    config.logger = Rails.logger
    config.log_headers = true
    config.log_data = true
    config.log_response = true
    config.log_benchmark = true
    # Do not print API keys / tokens in request bodies
    config.filter_parameters = %w[Apikey apikey password Password access_token refresh_token client_secret]
  end
end
