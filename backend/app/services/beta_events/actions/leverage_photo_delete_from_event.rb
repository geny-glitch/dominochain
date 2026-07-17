# frozen_string_literal: true

module BetaEvents
  module Actions
    class LeveragePhotoDeleteFromEvent < Base
      def call(context)
        photo = LeveragePhotos::ResolveTarget.call(
          user: context.beta,
          action: :delete,
          target_mode: context.event[:target_mode].presence || "random",
          photo_id: context.event[:photo_id]
        )
        raise ActionExecutionStopped.new(:no_eligible_photo) if photo.nil?

        photo_id = photo.id
        photo.permanently_delete!
        context.leverage_photo_id = photo_id
      end
    end
  end
end
