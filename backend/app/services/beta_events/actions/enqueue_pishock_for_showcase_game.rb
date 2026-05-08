# frozen_string_literal: true

module BetaEvents
  module Actions
    # Only applies when event is showcase_game / score_time_applied.
    class EnqueuePishockForShowcaseGame < Base
      def call(context)
        ev = context.event
        return unless ev.source == :showcase_game && ev.kind == :score_time_applied

        game_kind = ev[:game_kind].to_s
        beta = context.beta

        case game_kind
        when "snake"
          PishockShockJob.perform_later(beta.id, ShowcaseGameConfig.pishock_intensity(1, beta), 1)
        when "tetris"
          lines = ev[:lines].to_i.clamp(1, 8)
          PishockShockJob.perform_later(beta.id, ShowcaseGameConfig.pishock_intensity(lines, beta), lines)
        end
      end
    end
  end
end
