# frozen_string_literal: true

module BetaEvents
  # Mutable execution context passed between consequence actions.
  class Context
    attr_reader :beta, :event
    attr_accessor :addition, :chaster_lock_snapshot, :leverage_photo_id

    def initialize(beta:, event:)
      @beta = beta
      @event = event
      @addition = nil
      @chaster_lock_snapshot = nil
      @leverage_photo_id = nil
    end
  end
end
