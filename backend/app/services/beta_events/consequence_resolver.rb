# frozen_string_literal: true

module BetaEvents
  # Resolves ordered executable actions + config for a DomainEvent.
  class ConsequenceResolver
    ResolvedAction = Struct.new(:executor, :possibility_id, :config, keyword_init: true)

    class << self
      def resolved_actions_for(event)
        source_def = SourceRegistry.for_event(event)
        return [] unless source_def

        event_def = source_def.event(event.kind)
        return [] unless event_def

        case event_def.mode
        when :fixed
          resolve_fixed(event_def, event)
        when :payload, :configurable
          resolve_payload(event, event_def)
        else
          []
        end
      end

      # Back-compat helper used by older call sites/tests.
      def actions_for(event)
        resolved_actions_for(event).map(&:executor)
      end

      private

      def resolve_fixed(event_def, event)
        (event_def.bindings || []).filter_map do |binding|
          possibility_id = binding[:possibility_id].to_s
          config = ActionRegistry.resolve_binding_config(binding, event)
          next if config.nil?

          executor = ActionRegistry.executor_for(possibility_id)
          next unless executor

          ResolvedAction.new(
            executor: executor,
            possibility_id: possibility_id,
            config: config
          )
        end
      end

      def resolve_payload(event, event_def)
        possibility_id = resolve_possibility_id(event)
        return [] if possibility_id.blank?

        allowed = event_def.allowed
        if allowed.present? && !allowed.include?(possibility_id)
          return []
        end

        executor = ActionRegistry.executor_for(possibility_id)
        return [] unless executor

        config = ActionRegistry.normalize_config(possibility_id, event.payload)
        [
          ResolvedAction.new(
            executor: executor,
            possibility_id: possibility_id,
            config: config
          )
        ]
      end

      def resolve_possibility_id(event)
        raw = event[:possibility_id].presence || event[:action].presence
        return raw.to_s if raw.present? && ActionRegistry.find(raw)

        ActionRegistry.possibility_id_for_legacy_action(raw)
      end
    end
  end
end
