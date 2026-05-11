# frozen_string_literal: true

module BetaEvents
  # Maps event (source + kind) to ordered action classes (consequences).
  class ConsequenceRegistry
    def self.actions_for(event)
      key = [ event.source, event.kind ]
      case key
      when [ :showcase_game, :score_time_applied ]
        [
          Actions::EnqueuePishockForShowcaseGame,
          Actions::ChasterAddTimeFromEvent,
          Actions::RecordShowcaseLimiterFromEvent
        ]
      when [ :showcase_backdoor, :time_committed ]
        [
          Actions::ChasterAddTimeFromEvent,
          Actions::RecordShowcaseLimiterFromEvent
        ]
      when [ :strava_goal, :failed_penalty ]
        [ Actions::ChasterAddTimeFromEvent ]
      when [ :api_chaster, :add_time ]
        [ Actions::ChasterAddTimeFromEvent ]
      when [ :cigarette, :smoked_add_time ]
        [ Actions::ChasterAddTimeFromEvent ]
      else
        []
      end
    end
  end
end
