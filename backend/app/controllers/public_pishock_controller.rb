# frozen_string_literal: true

class PublicPishockController < ApplicationController
  before_action :load_public_pishock_context

  def show
  end

  def shock
    intensity = params[:intensity].to_i.clamp(0, 100)
    duration = params[:duration].to_i.clamp(1, 5)

    result = PishockService.shock!(user: @beta, intensity: intensity, duration: duration)

    case result
    when :ok
      PosthogProductAnalytics.pishock_zap(@beta, intensity: intensity, duration: duration, source: "public_page")
      notify_beta!(intensity: intensity, duration: duration)
      render json: { ok: true, message: t("public_pishock.flash.sent"), intensity: intensity, duration: duration }
    when :auth_error
      render json: { ok: false, error: t("public_pishock.flash.auth_error") }, status: :unprocessable_entity
    when :device_error
      render json: { ok: false, error: t("public_pishock.flash.device_error") }, status: :unprocessable_entity
    when :skipped
      render json: { ok: false, error: t("public_pishock.flash.skipped") }, status: :unprocessable_entity
    else
      render json: { ok: false, error: t("public_pishock.flash.error") }, status: :unprocessable_entity
    end
  end

  private

  def load_public_pishock_context
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render("showcase/not_found", status: :not_found) unless @beta&.public_pishock_enabled?

    @nickname = @beta.nickname
  end

  def notify_beta!(intensity:, duration:)
    @beta.devices.find_each do |device|
      FcmService.send_pishock_zap_notification(
        device: device,
        intensity: intensity,
        duration: duration
      )
    end
  end
end
