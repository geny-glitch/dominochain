# frozen_string_literal: true

if Rails.env.production?
  require Rails.root.join("lib/middleware/database_connection_retry")

  Rails.application.config.middleware.insert_before 0, Middleware::DatabaseConnectionRetry
end
