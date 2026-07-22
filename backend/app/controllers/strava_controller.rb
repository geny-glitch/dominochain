# frozen_string_literal: true

class StravaController < ApplicationController
  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_strava_configured!, only: [ :connect, :callback ]
  before_action :require_strava_connected!, only: [ :create_goal, :update_goal, :check_goal, :preview_check, :refresh_activities ]
  before_action :set_goal, only: [ :update_goal, :destroy_goal, :check_goal, :preview_check, :refresh_activities ]

  def connect
    state = SecureRandom.hex(24)
    session[:strava_oauth_state] = state

    redirect_to StravaService.authorization_url(redirect_uri: strava_callback_url, state: state), allow_other_host: true
  end

  def callback
    if params[:state] != session[:strava_oauth_state]
      redirect_to beta_sources_strava_path, alert: t("flash.strava.oauth_invalid_state")
      return
    end
    session.delete(:strava_oauth_state)

    if params[:error].present?
      redirect_to beta_sources_strava_path, alert: t("flash.strava.oauth_error", message: params[:error].to_s)
      return
    end

    code = params[:code].to_s
    if code.blank?
      redirect_to beta_sources_strava_path, alert: t("flash.strava.oauth_missing_code")
      return
    end

    tokens = StravaService.exchange_code_for_tokens(code: code)
    current_user.update!(
      strava_access_token: tokens[:access_token],
      strava_refresh_token: tokens[:refresh_token],
      strava_token_expires_at: tokens[:expires_at],
      strava_athlete_id: tokens[:athlete_id]
    )

    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: 'strava_connected'
    )
    redirect_to beta_sources_strava_path, notice: t("flash.strava.connected")
  rescue StravaService::Error => e
    redirect_to beta_sources_strava_path, alert: t("flash.strava.error", message: e.message)
  end

  def disconnect
    StravaService.new(current_user).disconnect!
    PostHog.capture(distinct_id: current_user.posthog_distinct_id, event: 'strava_disconnected')
    redirect_to beta_sources_strava_path, notice: t("flash.strava.disconnected")
  end

  def create_goal
    goal = current_user.strava_goals.new(goal_params)
    goal.chaster_penalty_seconds = 0
    goal.save!
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: 'strava_goal_created',
      properties: { goal_name: goal.name, window_days: goal.window_days }
    )
    PosthogProductAnalytics.configured_source(current_user, name: "strava")
    redirect_to beta_strava_goal_show_path(goal), notice: t("flash.strava.goal_created", name: goal.name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_strava_path, alert: e.record.errors.full_messages.join(", ")
  end

  def update_goal
    @goal.assign_attributes(goal_params)
    @goal.save!
    PosthogProductAnalytics.configured_source(current_user, name: "strava")
    redirect_to beta_strava_goal_show_path(@goal), notice: t("flash.strava.goal_updated", name: @goal.name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_strava_goal_show_path(@goal), alert: e.record.errors.full_messages.join(", ")
  end

  def destroy_goal
    name = @goal.name
    goal_id = @goal.id
    @goal.destroy!
    current_user.strava_config&.remove_scenarios_for_goal!(goal_id)
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: 'strava_goal_destroyed',
      properties: { goal_name: name }
    )
    redirect_to beta_sources_strava_path, notice: t("flash.strava.goal_destroyed", name:)
  end

  def check_goal
    check = StravaGoalEvaluator.new(current_user).evaluate_goal!(@goal, due_at: check_due_at)
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: 'strava_goal_checked',
      properties: { goal_name: @goal.name, status: check.status, valid_count: check.valid_count, required_count: check.required_count }
    )
    redirect_to beta_strava_goal_show_path(@goal), notice: strava_check_notice(check)
  rescue StravaService::Unauthorized
    redirect_to beta_strava_goal_show_path(@goal), alert: t("flash.strava.not_connected")
  rescue StravaService::Error, ChasterService::Error => e
    redirect_to beta_strava_goal_show_path(@goal), alert: t("flash.strava.check_impossible", message: e.message)
  end

  def preview_check
    preview = StravaGoalEvaluator.new(current_user).preview_goal(@goal, due_at: check_due_at)
    flash[:strava_preview] = {
      status: preview[:status],
      valid_count: preview[:valid_count],
      required_count: preview[:required_count],
      total_count: preview[:total_count],
      period_start_at: preview[:period_start_at].iso8601,
      period_end_at: preview[:period_end_at].iso8601,
      due_at: preview[:due_at].iso8601
    }
    redirect_to beta_strava_goal_show_path(@goal, due: preview_due_param)
  rescue StravaService::Unauthorized
    redirect_to beta_strava_goal_show_path(@goal), alert: t("flash.strava.not_connected")
  rescue StravaService::Error => e
    redirect_to beta_strava_goal_show_path(@goal), alert: t("flash.strava.check_impossible", message: e.message)
  end

  def refresh_activities
    redirect_to beta_strava_goal_show_path(@goal, show_all: params[:show_all], page: params[:page]),
      notice: t("flash.strava.activities_refreshed")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.strava.beta_only")
  end

  def require_strava_configured!
    return if StravaService.configured?

    redirect_to beta_sources_strava_path, alert: t("flash.strava.not_configured")
  end

  def require_strava_connected!
    return if current_user.reload.strava_access_token.present?

    redirect_to beta_sources_strava_path, alert: t("flash.strava.connect_first")
  end

  def set_goal
    @goal = current_user.strava_goals.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_sources_strava_path, alert: t("flash.strava.goal_not_found")
  end

  def goal_params
    p = params.permit(
      :name,
      :enabled,
      :required_count,
      :window_preset,
      :window_days,
      :check_time,
      :min_duration_minutes,
      :min_calories,
      :strava_sport_type,
      :activity_types,
      :device_names
    )

    {
      name: p[:name].to_s.strip,
      enabled: p[:enabled] == "1",
      required_activity_count: p[:required_count].to_i,
      window_days: window_days_param(p),
      check_time_minutes: check_time_minutes_param(p[:check_time]),
      time_zone: current_user.effective_time_zone,
      min_duration_seconds: positive_integer_or_nil(p[:min_duration_minutes])&.*(60),
      min_calories: positive_integer_or_nil(p[:min_calories]),
      activity_types: merged_activity_types_param(p),
      device_names: p[:device_names].to_s
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

  def preview_due_param
    params[:due].to_s == "next" ? "next" : nil
  end

  def strava_check_notice(check)
    case check.status
    when "passed"
      t(
        "flash.strava.check_passed",
        valid: check.valid_count,
        required: check.required_count,
        days: check.window_days
      )
    when "failed"
      t(
        "flash.strava.check_failed",
        valid: check.valid_count,
        required: check.required_count,
        days: check.window_days,
        penalty_minutes: check.chaster_penalty_seconds / 60
      )
    else
      t(
        "flash.strava.check_chaster_failed",
        valid: check.valid_count,
        required: check.required_count,
        days: check.window_days,
        chaster_error: check.chaster_error.to_s
      )
    end
  end
end
