# frozen_string_literal: true

class BetaZapProgramsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_beta_role!

  def disarm
    program = current_user.zap_programs.find(params[:id])
    program.disarm!
    redirect_to beta_actions_pishock_path, notice: t("zap_program.flash.disarmed")
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_actions_pishock_path, alert: t("zap_program.flash.program_missing")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.chaster.beta_only")
  end
end
