# frozen_string_literal: true

module BetaEvents
  # Maps event (source + kind) to ordered action classes (consequences).
  class ConsequenceRegistry
    WALLPAPER_KINDS = %i[
      mismatch_add_time
      mismatch_freeze
      permissions_lost
      app_unreachable
      enforcement_unfreeze
    ].freeze

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
        strava_actions_for(event)
      when [ :api_chaster, :add_time ], [ :puryfi, :add_time ]
        [ Actions::ChasterAddTimeFromEvent ]
      when [ :cigarette, :smoked_add_time ]
        [ Actions::ChasterAddTimeFromEvent ]
      when [ :wallpaper, :enforcement_unfreeze ]
        [ Actions::ChasterUnfreezeFromEvent ]
      else
        if event.source == :wallpaper
          sanction_actions_for(event)
        else
          []
        end
      end
    end

    def self.strava_actions_for(event)
      action = event[:action].to_s
      return [ Actions::ChasterAddTimeFromEvent ] if action.blank?

      sanction_actions_for(event)
    end

    def self.wallpaper_actions_for(event)
      sanction_actions_for(event)
    end

    def self.sanction_actions_for(event)
      case event[:action].to_s
      when "chaster_add_time"
        [ Actions::ChasterAddTimeFromEvent ]
      when "chaster_freeze"
        [ Actions::ChasterFreezeFromEvent ]
      when "pishock"
        [ Actions::EnqueuePishockFromEvent ]
      when "leverage_photo_lock", "leverage_photo_start", "leverage_photo_add_time"
        [ Actions::LeveragePhotoLockFromEvent ]
      when "leverage_photo_delete"
        [ Actions::LeveragePhotoDeleteFromEvent ]
      else
        []
      end
    end
  end
end
