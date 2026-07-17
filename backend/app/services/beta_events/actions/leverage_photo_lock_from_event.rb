# frozen_string_literal: true

module BetaEvents
  module Actions
    class LeveragePhotoLockFromEvent < Base
      def call(context)
        seconds = context.config_value(:seconds, :seconds).to_i
        raise ActionExecutionStopped.new(:missing_seconds) unless seconds.positive?

        photo = LeveragePhotos::ResolveTarget.call(
          user: context.beta,
          action: :lock,
          target_mode: context.config_value(:target_mode, :target_mode).presence || "random",
          photo_id: context.config_value(:photo_id, :photo_id)
        )
        raise ActionExecutionStopped.new(:no_eligible_photo) if photo.nil?

        if photo.can_add_time?
          LeveragePhotos::AddTimeServer.new(photo: photo, added_seconds: seconds).call!
        elsif photo.can_start_timer?
          LeveragePhotos::StartTimerServer.new(photo: photo, duration_seconds: seconds).call!
        else
          raise ActionExecutionStopped.new(:no_eligible_photo)
        end

        context.leverage_photo_id = photo.id
      rescue LeveragePhotos::StartTimerServer::Error => e
        raise ActionExecutionStopped.new(:leverage_start_failed, e.message.to_s.truncate(500))
      rescue LeveragePhotos::AddTimeServer::Error => e
        raise ActionExecutionStopped.new(:leverage_add_time_failed, e.message.to_s.truncate(500))
      end
    end
  end
end
