# frozen_string_literal: true

class ChasterController < ApplicationController
  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_chaster_configured!, only: [:connect]

  def connect
    state = SecureRandom.hex(32)
    session[:chaster_oauth_state] = state

    redirect_uri = chaster_callback_url
    url = ChasterService.authorization_url(redirect_uri: redirect_uri, state: state)
    redirect_to url, allow_other_host: true
  end

  def callback
    if params[:state] != session[:chaster_oauth_state]
      redirect_to beta_actions_chaster_path, alert: "Connexion Chaster annulée (état invalide)."
      return
    end
    session.delete(:chaster_oauth_state)

    if params[:error].present?
      redirect_to beta_actions_chaster_path, alert: "Chaster: #{params[:error_description] || params[:error]}"
      return
    end

    code = params[:code]
    unless code.present?
      redirect_to beta_actions_chaster_path, alert: "Code d'autorisation manquant."
      return
    end

    redirect_uri = chaster_callback_url
    tokens = ChasterService.exchange_code_for_tokens(code: code, redirect_uri: redirect_uri)

    expires_at = tokens[:expires_in].present? ? Time.current + tokens[:expires_in].seconds : nil
    current_user.update!(
      chaster_access_token: tokens[:access_token],
      chaster_refresh_token: tokens[:refresh_token],
      chaster_token_expires_at: expires_at
    )

    redirect_to beta_actions_chaster_path, notice: "Chaster connecté avec succès."
  rescue ChasterService::Error => e
    redirect_to beta_actions_chaster_path, alert: "Erreur Chaster: #{e.message}"
  end

  def disconnect
    if active_chaster_lock?
      redirect_to beta_actions_chaster_path, alert: "Impossible de déconnecter Chaster tant qu'un lock est actif."
      return
    end

    current_user.update!(
      chaster_access_token: nil,
      chaster_refresh_token: nil,
      chaster_token_expires_at: nil
    )
    redirect_to beta_actions_chaster_path, notice: "Chaster déconnecté."
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: "Accès réservé aux betas."
  end

  def require_chaster_configured!
    return if ChasterService.configured?

    redirect_to beta_actions_chaster_path, alert: "Chaster n'est pas configuré. Contactez l'administrateur."
  end

  def active_chaster_lock?
    ChasterService.new(current_user).current_lock.present?
  rescue ChasterService::Unauthorized, ChasterService::Error
    current_user.chaster_locks.active.exists?
  end
end
