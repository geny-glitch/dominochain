# frozen_string_literal: true

class PublicPishockController < ApplicationController
  before_action :load_public_pishock_context

  def show
    if @beta.pishock_enabled? && BetaCatalog.new(@beta).action_enabled?("pishock")
      @zap_program = ZapProgram.find_or_create_for!(beta: @beta, source: "public")
      @zap_beta = @beta
      @zap_slots = @zap_program.zap_slots.to_a
      @editing_slot = @zap_slots.find { |s| s.id.to_s == params[:edit].to_s }
      @zap_program_paths = public_zap_program_paths(@beta.nickname)
    end
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

  def public_zap_program_paths(nickname)
    {
      arm: public_zap_program_arm_path(nickname),
      disarm: public_zap_program_disarm_path(nickname),
      create_slot: public_zap_program_slots_path(nickname),
      update_slot: ->(slot) { public_zap_program_slot_path(nickname, slot) },
      destroy_slot: ->(slot) { public_zap_program_slot_destroy_path(nickname, slot) },
      try_slot: ->(slot) { public_zap_program_slot_try_path(nickname, slot) },
      try_ephemeral: public_zap_program_try_path(nickname),
      starter: ->(key) { public_zap_program_starter_path(nickname, key) },
      edit: ->(slot) { public_pishock_path(nickname, edit: slot.id) },
      show: public_pishock_path(nickname)
    }
  end
  helper_method :public_zap_program_paths
end
