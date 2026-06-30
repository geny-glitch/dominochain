# frozen_string_literal: true

module BetaEvents
  module Actions
    class EnqueuePishockFromEvent < Base
      def call(context)
        beta = context.beta
        ev = context.event
        return unless beta.pishock_enabled?

        intensity = ev[:pishock_intensity] || ev[:intensity]
        duration = ev[:pishock_duration] || ev[:duration]
        raise ActionExecutionStopped.new(:missing_pishock_params) if intensity.blank? || duration.blank?

        scaled_intensity = ShowcaseGameConfig.pishock_intensity(intensity.to_i, beta)
        PishockShockJob.perform_later(beta.id, scaled_intensity, duration.to_i.clamp(1, 15))
      end
    end
  end
end
