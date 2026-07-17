# frozen_string_literal: true

module BetaEvents
  # Resolves binding config from a DomainEvent for fixed source pipelines.
  module ConfigResolvers
    module_function

    def resolve(name, event)
      case name.to_sym
      when :from_event_seconds
        from_event_seconds(event)
      when :showcase_score
        showcase_score(event)
      else
        raise ArgumentError, "Unknown config resolver: #{name}"
      end
    end

    def from_event_seconds(event)
      { seconds: event[:seconds] }
    end

    # Maps showcase game score into pishock.shock intensity/duration.
    # Returns nil to skip the binding (quiz/dino have no shock mapping).
    def showcase_score(event)
      case event[:game_kind].to_s
      when "snake"
        { intensity: 1, duration: 1 }
      when "tetris"
        lines = event[:lines].to_i.clamp(1, 8)
        { intensity: lines, duration: lines }
      else
        nil
      end
    end
  end
end
