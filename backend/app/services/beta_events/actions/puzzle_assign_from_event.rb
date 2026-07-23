# frozen_string_literal: true

module BetaEvents
  module Actions
    class PuzzleAssignFromEvent < Base
      def call(context)
        result = PuzzleSessionCreator.new(
          user: context.beta,
          origin: "scenario",
          image_source: context.config_value(:image_source, :image_source).presence || "leverage_photo",
          piece_count: context.config_value(:piece_count, :piece_count),
          reference_mode: context.config_value(:reference_mode, :reference_mode),
          time_limit_seconds: context.config_value(:time_limit_seconds, :time_limit_seconds),
          target_mode: context.config_value(:target_mode, :target_mode).presence || "random",
          photo_id: context.config_value(:photo_id, :photo_id),
          notify: true
        ).call

        raise ActionExecutionStopped.new(result.error || :assign_failed) unless result.ok

        context.puzzle_session_id = result.session.id
      end
    end
  end
end
