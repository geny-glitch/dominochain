# frozen_string_literal: true

module Api
  class PishockController < ApplicationController
    include ApiAuthenticatable

    def shock
      return head :forbidden unless current_user.beta?

      catalog = BetaCatalog.new(current_user)
      unless current_user.pishock_enabled? && catalog.action_enabled?("pishock")
        return render json: { error: "PiShock disabled." }, status: :unprocessable_entity
      end

      intensity = params[:intensity].to_i
      duration = params[:duration].to_i.clamp(1, 15)
      return render json: { error: "Invalid shock params." }, status: :unprocessable_entity unless intensity.positive?

      scaled_intensity = ShowcaseGameConfig.pishock_intensity(intensity, current_user)
      PishockShockJob.perform_later(current_user.id, scaled_intensity, duration)

      render json: { ok: true, intensity: scaled_intensity, duration: duration }
    end
  end
end
