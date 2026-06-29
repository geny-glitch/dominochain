# frozen_string_literal: true

module BetaAccessControl
  extend ActiveSupport::Concern

  included do
    before_action :require_beta_access!
  end

  private

  def require_beta_access!
    @nickname = params[:nickname]
    @beta = User.find_by(nickname: @nickname)
    return redirect_to(root_path, alert: I18n.t("flash.beta_access.beta_not_found")) unless @beta

    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path, alert: I18n.t("flash.beta_access.sign_in_to_access")
      return
    end

    boss_control = Control.find_by(beta: @beta, boss: current_user, status: :accepted)
    is_admin = current_user.admin?

    unless boss_control || is_admin
      redirect_to control_accept_from_link_path(@nickname)
      return
    end

    @devices = @beta.devices.order(created_at: :desc)
    # Un beta n'a qu'un device actif à la fois : on utilise toujours le dernier enregistré
    @device = @devices.order(created_at: :desc).first
    @device_id = @device&.device_id
    if @device.nil?
      # Boss/Admin a le contrôle mais le beta n'a pas de device : éviter la boucle avec control_accept_from_link
      redirect_target = current_user.admin? ? admin_path : dashboard_path
      return redirect_to redirect_target, alert: I18n.t("flash.beta_access.no_device", nickname: @beta.nickname)
    end
  end
end
