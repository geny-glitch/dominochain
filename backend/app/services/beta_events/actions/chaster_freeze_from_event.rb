# frozen_string_literal: true

module BetaEvents
  module Actions
    class ChasterFreezeFromEvent < Base
      def call(context)
        beta = context.beta
        ev = context.event
        service = ChasterService.new(beta)
        lock = resolve_lock(service, ev)
        unless lock&.dig(:id).present?
          raise ActionExecutionStopped.new(:no_chaster_lock)
        end

        service.freeze_lock(
          lock[:id],
          source: ev[:source].presence || "wallpaper",
          summary: ev[:summary],
          metadata: ev[:metadata] || {}
        )
        context.chaster_lock_snapshot = lock
      rescue ChasterService::Unauthorized
        raise ActionExecutionStopped.new(:chaster_unauthorized)
      rescue ChasterService::Error => e
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
    end
  end
end
