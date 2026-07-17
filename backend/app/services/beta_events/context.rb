# frozen_string_literal: true

module BetaEvents
  # Mutable execution context passed between consequence actions.
  class Context
    attr_reader :beta, :event
    attr_accessor :addition, :chaster_lock_snapshot, :leverage_photo_id, :action_config

    def initialize(beta:, event:, action_config: nil)
      @beta = beta
      @event = event
      @addition = nil
      @chaster_lock_snapshot = nil
      @leverage_photo_id = nil
      @action_config = action_config
    end

    def config_value(key, *fallback_keys)
      cfg = action_config || {}
      sym = key.to_sym
      return cfg[sym] if cfg.key?(sym)

      fallback_keys.each do |fk|
        v = event[fk]
        return v unless v.nil?
      end
      nil
    end
  end
end
