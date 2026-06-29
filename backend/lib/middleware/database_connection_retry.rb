# frozen_string_literal: true

module Middleware
  # Clears stale pool connections and retries once when Fly Postgres drops an idle socket.
  class DatabaseConnectionRetry
    RETRIABLE_ERRORS = [
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::ConnectionFailed,
      PG::ConnectionBad
    ].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      attempt = 0
      begin
        @app.call(env)
      rescue *RETRIABLE_ERRORS => e
        attempt += 1
        raise e if attempt >= 2

        Rails.logger.warn(
          "[DatabaseConnectionRetry] #{e.class}: #{e.message} — clearing pool and retrying request"
        )
        ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
        retry
      end
    end
  end
end
