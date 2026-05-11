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
      redirect_to beta_actions_chaster_path, alert: t("flash.chaster.oauth_invalid_state")
      return
    end
    session.delete(:chaster_oauth_state)

    if params[:error].present?
      redirect_to beta_actions_chaster_path, alert: t("flash.chaster.oauth_error", message: (params[:error_description].presence || params[:error]).to_s)
      return
    end

    code = params[:code]
    unless code.present?
      redirect_to beta_actions_chaster_path, alert: t("flash.chaster.oauth_missing_code")
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

    PostHog.capture(distinct_id: current_user.posthog_distinct_id, event: 'chaster_connected')
    redirect_to beta_actions_chaster_path, notice: t("flash.chaster.connected")
  rescue ChasterService::Error => e
    redirect_to beta_actions_chaster_path, alert: t("flash.chaster.error", message: e.message)
  end

  def disconnect
    if active_chaster_lock?
      redirect_to beta_actions_chaster_path, alert: t("flash.chaster.disconnect_lock_active")
      return
    end

    current_user.update!(
      chaster_access_token: nil,
      chaster_refresh_token: nil,
      chaster_token_expires_at: nil
    )
    PostHog.capture(distinct_id: current_user.posthog_distinct_id, event: 'chaster_disconnected')
    redirect_to beta_actions_chaster_path, notice: t("flash.chaster.disconnected")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.chaster.beta_only")
  end

  def require_chaster_configured!
    return if ChasterService.configured?

    redirect_to beta_actions_chaster_path, alert: t("flash.chaster.not_configured")
  end

  def active_chaster_lock?
    ChasterService.new(current_user).current_lock.present?
  rescue ChasterService::Unauthorized, ChasterService::Error
    current_user.chaster_locks.active.exists?
  end
end
