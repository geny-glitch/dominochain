# frozen_string_literal: true

class BossZapProgramsController < ApplicationController
  include ZapProgramEditor

  before_action :authenticate_user!
  before_action :require_boss_role!
  before_action :load_control_and_program!
  before_action :load_slot!, only: %i[update_slot destroy_slot try_slot]

  def show
    assign_editor_locals!(@program)
    @zap_program_paths = {
      arm: boss_zap_program_arm_path(@beta.nickname),
      disarm: boss_zap_program_disarm_path(@beta.nickname),
      create_slot: boss_zap_program_slots_path(@beta.nickname),
      update_slot: ->(slot) { boss_zap_program_slot_path(@beta.nickname, slot) },
      destroy_slot: ->(slot) { boss_zap_program_slot_destroy_path(@beta.nickname, slot) },
      try_slot: ->(slot) { boss_zap_program_slot_try_path(@beta.nickname, slot) },
      try_ephemeral: boss_zap_program_try_path(@beta.nickname),
      starter: ->(key) { boss_zap_program_starter_path(@beta.nickname, key) },
      edit: ->(slot) { boss_zap_program_path(@beta.nickname, edit: slot.id) },
      show: boss_zap_program_path(@beta.nickname)
    }
  end

  def arm
    arm_program!(@program)
  end

  def disarm
    disarm_program!(@program)
  end

  def create_slot
    create_slot!(@program)
  end

  def update_slot
    update_slot!(@program, @slot)
  end

  def destroy_slot
    destroy_slot!(@program, @slot)
  end

  def try_slot
    try_slot!(@program, @slot)
  end

  def try_ephemeral
    try_ephemeral!(@program)
  end

  def add_starter
    add_starter!(@program, params[:starter])
  end

  private

  def require_boss_role!
    return if current_user.boss?

    redirect_to beta_dashboard_path, alert: t("flash.dashboard.boss_only")
  end

  def load_control_and_program!
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return redirect_to dashboard_path, alert: t("zap_program.flash.beta_not_found") unless @beta

    @control = current_user.controls.accepted.find_by(beta_id: @beta.id)
    return redirect_to dashboard_path, alert: t("zap_program.flash.not_controlling") unless @control

    unless @beta.pishock_enabled? && BetaCatalog.new(@beta).action_enabled?("pishock")
      return redirect_to dashboard_path, alert: t("zap_program.flash.pishock_unavailable")
    end

    @program = ZapProgram.find_or_create_for!(beta: @beta, source: "boss", boss: current_user)
    @zap_beta = @beta
  end

  def load_slot!
    @slot = @program.zap_slots.find(params[:slot_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to boss_zap_program_path(@beta.nickname), alert: t("zap_program.flash.slot_missing")
  end

  def redirect_back_program(_program, notice: nil, alert: nil)
    redirect_to boss_zap_program_path(@beta.nickname), notice: notice, alert: alert
  end
end
