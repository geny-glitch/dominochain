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
      catalog = BetaCatalog.new(@beta)
      return :source_disabled unless catalog.source_enabled_for_event_source?(@event.source)

      executed = false
      ConsequenceResolver.resolved_actions_for(@event).each do |resolved|
        next unless catalog.action_enabled_for_class?(resolved.executor)

        executed = true
        @context.action_config = resolved.config
        resolved.executor.new.call(@context)
      end
      executed ? :ok : :no_enabled_actions
    rescue ActionExecutionStopped
      raise
    end

    def call_safe
      call
    rescue ActionExecutionStopped
      :stopped
    end
  end
end
