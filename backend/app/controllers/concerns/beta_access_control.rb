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
    return redirect_to(root_path, alert: "Beta non trouvé.") unless @beta

    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path, alert: "Connectez-vous pour accéder."
      return
    end

    boss_control = Control.find_by(beta: @beta, boss: current_user, status: :accepted)
    is_admin = current_user.admin?

    unless boss_control || is_admin
      redirect_to control_accept_from_link_path(@nickname)
      return
    end

    @devices = @beta.devices
    @device_id = params[:device_id]
    @device = if @device_id.present?
                @devices.find_by(device_id: @device_id)
              else
                @devices.first
              end
    @device_id = @device&.device_id if @device && @device_id.blank?

    if @devices.many? && @device.nil?
      return redirect_to wallpaper_upload_path(@nickname), alert: "Sélectionnez un device."
    end
    if @device.nil?
      # Boss/Admin a le contrôle mais le beta n'a pas de device : éviter la boucle avec control_accept_from_link
      redirect_target = current_user.admin? ? admin_path : dashboard_path
      return redirect_to redirect_target, alert: "Aucun device enregistré. Le beta #{@beta.nickname} doit ouvrir l'app d'abord."
    end
  end
end
