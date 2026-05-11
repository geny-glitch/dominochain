# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_boss_role!

  def show
    @controlled_betas = current_user.controls.accepted.includes(:beta)
    @pending_control_requests = current_user.control_requests_received.pending.includes(:beta)
  end

  private

  def require_boss_role!
    return if current_user.boss?

    redirect_to beta_dashboard_path, alert: t("flash.dashboard.boss_only")
  end
end
