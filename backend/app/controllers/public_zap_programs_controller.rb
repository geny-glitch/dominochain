# frozen_string_literal: true

class PublicZapProgramsController < ApplicationController
  include ZapProgramEditor

  before_action :load_public_program!
  before_action :load_slot!, only: %i[update_slot destroy_slot try_slot]

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

  def load_public_program!
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render("showcase/not_found", status: :not_found) unless @beta&.public_pishock_enabled?

    unless @beta.pishock_enabled? && BetaCatalog.new(@beta).action_enabled?("pishock")
      return redirect_to public_pishock_path(@beta.nickname), alert: t("zap_program.flash.pishock_unavailable")
    end

    @program = ZapProgram.find_or_create_for!(beta: @beta, source: "public")
    @zap_beta = @beta
  end

  def load_slot!
    @slot = @program.zap_slots.find(params[:slot_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to public_pishock_path(@beta.nickname), alert: t("zap_program.flash.slot_missing")
  end

  def redirect_back_program(_program, notice: nil, alert: nil)
    redirect_to public_pishock_path(@beta.nickname), notice: notice, alert: alert
  end
end
