# frozen_string_literal: true

module BetaEvents
  class ActionExecutionStopped < StandardError
    attr_reader :reason, :detail

    def initialize(reason, detail = nil)
      @reason = reason
      @detail = detail
      super(reason.to_s)
    end
  end

  # Runs ordered consequence actions for a domain event.
  class ActionExecutor
    attr_reader :context

    def initialize(beta:, event:, context: nil)
      @beta = beta
      @event = event
      @context = context || Context.new(beta: beta, event: event)
    end

    def call
      ConsequenceRegistry.actions_for(@event).each do |action_class|
        action_class.new.call(@context)
      end
      :ok
    rescue ActionExecutionStopped
      raise
    end

    def call_safe
      call
      :ok
    rescue ActionExecutionStopped
      :stopped
    end
  end
end
