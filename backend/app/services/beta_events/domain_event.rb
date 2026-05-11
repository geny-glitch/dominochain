# frozen_string_literal: true

module BetaEvents
  # Immutable description of something that happened (source + kind + payload).
  # Used for routing consequences and optional audit logging.
  class DomainEvent
    attr_reader :beta, :source, :kind, :payload, :occurred_at

    SOURCES = %i[showcase_game showcase_backdoor strava_goal api_chaster cigarette].freeze

    def initialize(beta:, source:, kind:, payload: {}, occurred_at: Time.current)
      @beta = beta
      @source = source.to_sym
      @kind = kind.to_sym
      @payload = payload.deep_symbolize_keys.freeze
      @occurred_at = occurred_at
    end

    def [](key)
      @payload[key.to_sym]
    end
  end
end
