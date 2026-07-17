# frozen_string_literal: true

class CornertimeSessionsController < ApplicationController
  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!

  def show
    @config = current_user.ensure_cornertime_config!
    @source_enabled = BetaCatalog.new(current_user).source_enabled?("cornertime")
    @config_payload = CornertimePayload.config_json(@config)
  end

  def create
    result = CornertimeSessionStarter.new(
      user: current_user,
      client: "web",
      device: nil,
      duration_minutes: params[:duration_minutes]
    ).call

    unless result.ok
      render json: { error: result.error }, status: result.http_status
      return
    end

    render json: {
      session: CornertimePayload.session_json(result.session),
      config: CornertimePayload.config_json(result.config)
    }, status: :created
  end

  def stop
    session = current_user.cornertime_sessions.find(params[:id])
    result = CornertimeSessionFinisher.new(session: session).call
    render json: {
      session: CornertimePayload.session_json(result.session),
      early_stop: result.early_stop,
      actions_executed: result.actions_executed
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: I18n.t("cornertime.errors.session_not_found") }, status: :not_found
  end

  def create_violation
    session = current_user.cornertime_sessions.find(params[:id])
    detected_at = parse_detected_at
    result = CornertimeViolationRecorder.new(
      session: session,
      motion_score: params[:motion_score].presence&.to_f,
      detected_at: detected_at,
      client_violation_id: params[:client_violation_id]
    ).call

    unless result.ok
      render json: {
        error: result.error,
        status: result.status,
        violation: result.violation && CornertimePayload.violation_json(result.violation)
      }.compact, status: result.http_status || :unprocessable_entity
      return
    end

    render json: {
      status: result.status,
      cooldown_remaining_seconds: result.cooldown_remaining_seconds.to_i,
      violation: CornertimePayload.violation_json(result.violation),
      session: CornertimePayload.session_json(session.reload)
    }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: I18n.t("cornertime.errors.session_not_found") }, status: :not_found
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.beta.beta_only")
  end

  def parse_detected_at
    raw = params[:detected_at].presence
    return Time.current if raw.blank?

    Time.zone.parse(raw.to_s) || Time.current
  rescue ArgumentError, TypeError
    Time.current
  end
end
