# frozen_string_literal: true

module BetaEvents
  module Actions
    class ChasterAddTimeFromEvent < Base
      def call(context)
        beta = context.beta
        ev = context.event
        seconds = ev[:seconds]
        raise ActionExecutionStopped.new(:missing_seconds) if seconds.blank? || !seconds.to_i.positive?

        seconds = seconds.to_i
        service = ChasterService.new(beta)
        lock = resolve_lock(service, ev)
        unless lock&.dig(:id).present?
          on_no_lock(context, beta)
          raise ActionExecutionStopped.new(:no_chaster_lock)
        end

        service.add_time_to_lock(
          lock[:id],
          seconds,
          source: ev[:source].presence || default_source(context),
          summary: ev[:summary],
          metadata: ev[:metadata] || {}
        )
        context.chaster_lock_snapshot = lock
      rescue ChasterService::Unauthorized
        on_chaster_unauthorized(context)
        raise ActionExecutionStopped.new(:chaster_unauthorized)
      rescue ChasterService::Error => e
        on_chaster_error(context, e)
        raise ActionExecutionStopped.new(:chaster_error, e.message.to_s.truncate(500))
      end

      private

      def resolve_lock(service, ev)
        if ev[:lock_id].present?
          { id: ev[:lock_id].to_s }
        else
          service.current_lock
        end
      end

      def default_source(context)
        case context.event.source
        when :strava_goal then "strava_goal"
        when :cigarette then "cigarettes"
        when :showcase_game then "showcase_game"
        when :showcase_backdoor then "showcase_backdoor"
        when :wallpaper then "wallpaper"
        else "api"
        end
      end

      def on_no_lock(context, beta)
        msg = "Aucun cadenas Chaster actif."
        case context.event.source
        when :showcase_backdoor
          context.addition&.update(chaster_error: msg, chaster_applied: false)
        when :strava_goal
          # StravaGoalEvaluator records check in ensure block — status chaster_error set outside
        end
      end

      def on_chaster_unauthorized(context)
        case context.event.source
        when :showcase_backdoor
          context.addition&.update(chaster_error: "Chaster non connecté", chaster_applied: false) if context.addition&.persisted?
        end
      end

      def on_chaster_error(context, error)
        case context.event.source
        when :showcase_backdoor
          if context.addition&.persisted?
            context.addition.update(chaster_error: error.message.to_s.truncate(500), chaster_applied: false)
          end
        end
      end
    end
  end
end
