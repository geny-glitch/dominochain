# frozen_string_literal: true

module BetaEvents
  module Actions
    class EnqueuePishockFromEvent < Base
      def call(context)
        beta = context.beta
        return unless beta.pishock_enabled?

        intensity = context.config_value(:intensity, :pishock_intensity, :intensity)
        duration = context.config_value(:duration, :pishock_duration, :duration)
        raise ActionExecutionStopped.new(:missing_pishock_params) if intensity.blank? || duration.blank?

        scaled_intensity = ShowcaseGameConfig.pishock_intensity(intensity.to_i, beta)
        PishockShockJob.perform_later(beta.id, scaled_intensity, duration.to_i.clamp(1, 15))
      end
    end
  end
end
