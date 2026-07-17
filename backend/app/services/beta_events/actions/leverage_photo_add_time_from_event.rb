# frozen_string_literal: true

module BetaEvents
  module Actions
    class LeveragePhotoAddTimeFromEvent < Base
      def call(context)
        seconds = context.event[:seconds].to_i
        raise ActionExecutionStopped.new(:missing_seconds) unless seconds.positive?

        photo = LeveragePhotos::ResolveTarget.call(
          user: context.beta,
          action: :add_time,
          target_mode: context.event[:target_mode].presence || "random",
          photo_id: context.event[:photo_id]
        )
        raise ActionExecutionStopped.new(:no_eligible_photo) if photo.nil?

        LeveragePhotos::AddTimeServer.new(photo: photo, added_seconds: seconds).call!
        context.leverage_photo_id = photo.id
      rescue LeveragePhotos::AddTimeServer::Error => e
        raise ActionExecutionStopped.new(:leverage_add_time_failed, e.message.to_s.truncate(500))
      end
    end
  end
end
