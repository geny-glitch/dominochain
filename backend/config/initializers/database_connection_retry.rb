# frozen_string_literal: true

if Rails.env.production?
  Rails.application.config.middleware.insert_before 0, Middleware::DatabaseConnectionRetry
end
