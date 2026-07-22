# frozen_string_literal: true

module BetaEvents
  module Actions
    class LeveragePhotoDeleteFromEvent < Base
      def call(context)
        photo = LeveragePhotos::ResolveTarget.call(
          user: context.beta,
          action: :delete,
          target_mode: context.config_value(:target_mode, :target_mode).presence || "random",
          photo_id: context.config_value(:photo_id, :photo_id)
        )
        raise ActionExecutionStopped.new(:no_eligible_photo) if photo.nil?

        photo_id = photo.id
        photo.delete_original_from_sanction!
        context.leverage_photo_id = photo_id
      end
    end
  end
end
