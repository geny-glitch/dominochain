# frozen_string_literal: true

module BetaEvents
  module Actions
    class LeveragePhotoCropToProgressFromEvent < Base
      def call(context)
        session_id = context.event[:puzzle_session_id]
        raise ActionExecutionStopped.new(:missing_puzzle_session) if session_id.blank?

        session = PuzzleSession.find_by(id: session_id, user_id: context.beta.id)
        raise ActionExecutionStopped.new(:puzzle_session_not_found) if session.nil?
        raise ActionExecutionStopped.new(:missing_progress_snapshot) unless session.progress_snapshot.attached?

        photo = resolve_photo(context, session)
        raise ActionExecutionStopped.new(:no_eligible_photo) if photo.nil?

        LeveragePhotos::CropToProgress.call(photo: photo, snapshot: session.progress_snapshot)
        context.leverage_photo_id = photo.id
      end

      private

      def resolve_photo(context, session)
        if session.image_source == "leverage_photo" && session.leverage_photo.present?
          return session.leverage_photo
        end

        LeveragePhotos::ResolveTarget.call(
          user: context.beta,
          action: :crop_to_progress,
          target_mode: context.config_value(:target_mode, :target_mode).presence || "specific",
          photo_id: context.config_value(:photo_id, :photo_id).presence || session.leverage_photo_id
        )
      end
    end
  end
end
