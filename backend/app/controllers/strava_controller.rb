# frozen_string_literal: true

class StravaController < ApplicationController
  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_strava_configured!, only: [ :connect, :callback ]
  before_action :require_strava_connected!, only: [ :create_goal, :update_goal, :check_goal ]
  before_action :set_goal, only: [ :update_goal, :destroy_goal, :check_goal ]

  def connect
    state = SecureRandom.hex(24)
    session[:strava_oauth_state] = state

    redirect_to StravaService.authorization_url(redirect_uri: strava_callback_url, state: state), allow_other_host: true
  end

  def callback
    if params[:state] != session[:strava_oauth_state]
      redirect_to beta_sources_strava_path, alert: "Connexion Strava annulée (état invalide)."
      return
    end
    session.delete(:strava_oauth_state)

    if params[:error].present?
      redirect_to beta_sources_strava_path, alert: "Strava: #{params[:error]}"
      return
    end

    code = params[:code].to_s
    if code.blank?
      redirect_to beta_sources_strava_path, alert: "Code d'autorisation Strava manquant."
      return
    end

    tokens = StravaService.exchange_code_for_tokens(code: code)
    current_user.update!(
      strava_access_token: tokens[:access_token],
      strava_refresh_token: tokens[:refresh_token],
      strava_token_expires_at: tokens[:expires_at],
      strava_athlete_id: tokens[:athlete_id]
    )

    redirect_to beta_sources_strava_path, notice: "Strava connecté avec succès."
  rescue StravaService::Error => e
    redirect_to beta_sources_strava_path, alert: "Erreur Strava: #{e.message}"
  end

  def disconnect
    StravaService.new(current_user).disconnect!
    redirect_to beta_sources_strava_path, notice: "Strava déconnecté. Les objectifs Strava ont été désactivés."
  end

  def create_goal
    goal = current_user.strava_goals.create!(goal_params)
    redirect_to beta_sources_strava_path, notice: "Objectif Strava « #{goal.name} » créé."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_strava_path, alert: e.record.errors.full_messages.join(", ")
  end

  def update_goal
    @goal.update!(goal_params)
    redirect_to beta_sources_strava_path, notice: "Objectif Strava « #{@goal.name} » enregistré."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_strava_path, alert: e.record.errors.full_messages.join(", ")
  end

  def destroy_goal
    name = @goal.name
    @goal.destroy!
    redirect_to beta_sources_strava_path, notice: "Objectif Strava « #{name} » supprimé."
  end

  def check_goal
    check = StravaGoalEvaluator.new(current_user).evaluate_goal!(@goal, due_at: check_due_at)
    redirect_to beta_sources_strava_path, notice: strava_check_notice(check)
  rescue StravaService::Unauthorized
    redirect_to beta_sources_strava_path, alert: "Strava non connecté."
  rescue StravaService::Error, ChasterService::Error => e
    redirect_to beta_sources_strava_path, alert: "Vérification Strava impossible: #{e.message}"
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: "Accès réservé aux betas."
  end

  def require_strava_configured!
    return if StravaService.configured?

    redirect_to beta_sources_strava_path, alert: "Strava n'est pas configuré. Contacte l'administrateur."
  end

  def require_strava_connected!
    return if current_user.strava_access_token.present?

    redirect_to beta_sources_strava_path, alert: "Connecte Strava avant de gérer des objectifs."
  end

  def set_goal
    @goal = current_user.strava_goals.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_sources_strava_path, alert: "Objectif Strava introuvable."
  end

  def goal_params
    p = params.permit(
      :name,
      :enabled,
      :required_count,
      :window_preset,
      :window_days,
      :check_time,
      :time_zone,
      :min_duration_minutes,
      :min_calories,
      :strava_sport_type,
      :activity_types,
      :device_names,
      :chaster_penalty_minutes
    )

    {
      name: p[:name].to_s.strip,
      enabled: p[:enabled] == "1",
      required_activity_count: p[:required_count].to_i,
      window_days: window_days_param(p),
      check_time_minutes: check_time_minutes_param(p[:check_time]),
      time_zone: p[:time_zone].presence || Time.zone.tzinfo.name,
      min_duration_seconds: positive_integer_or_nil(p[:min_duration_minutes])&.*(60),
      min_calories: positive_integer_or_nil(p[:min_calories]),
      activity_types: merged_activity_types_param(p),
      device_names: p[:device_names].to_s,
      chaster_penalty_seconds: positive_integer_or_nil(p[:chaster_penalty_minutes]).to_i * 60
    }
  end

  def merged_activity_types_param(permitted)
    parts = []
    st = permitted[:strava_sport_type].to_s.strip
    parts << st if st.present? && StravaGoal::STRAVA_SPORT_TYPES.include?(st)
    permitted[:activity_types].to_s.split(/[\n,;]/).each do |segment|
      s = segment.strip
      parts << s if s.present?
    end
    parts.uniq.join(", ")
  end

  def positive_integer_or_nil(value)
    n = value.to_i
    n.positive? ? n : nil
  end

  def window_days_param(permitted_params)
    case permitted_params[:window_preset].to_s
    when "daily" then 1
    when "weekly" then 7
    else
      positive_integer_or_nil(permitted_params[:window_days]) || 7
    end
  end

  def check_time_minutes_param(value)
    hours, minutes = value.to_s.split(":", 2).map(&:to_i)
    minutes ||= 0
    return 0 unless hours.between?(0, 23) && minutes.between?(0, 59)

    hours * 60 + minutes
  end

  def check_due_at
    params[:due].to_s == "next" ? @goal.next_due_at : @goal.previous_due_at
  end

  def strava_check_notice(check)
    case check.status
    when "passed"
      "Objectif Strava validé: #{check.valid_count}/#{check.required_count} activités sur #{check.window_days} jours."
    when "failed"
      "Objectif Strava non validé: #{check.valid_count}/#{check.required_count} sur #{check.window_days} jours. #{check.chaster_penalty_seconds / 60} min ajoutées à Chaster."
    else
      "Objectif Strava non validé: #{check.valid_count}/#{check.required_count} sur #{check.window_days} jours. Chaster n'a pas pu être pénalisé: #{check.chaster_error}"
    end
  end
end
