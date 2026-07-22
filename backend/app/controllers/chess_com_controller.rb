# frozen_string_literal: true

class ChessComController < ApplicationController
  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_chess_platform_enabled!
  before_action :require_chess_com_verified!, only: [ :create_goal, :update_goal, :check_goal, :preview_check ]
  before_action :set_goal, only: [ :update_goal, :destroy_goal, :check_goal, :preview_check ]

  def link
    username = ChessComService.normalize_username(params[:username])
    if username.blank?
      redirect_to beta_sources_chess_path, alert: t("flash.chess.username_required")
      return
    end

    profile = ChessComService.new.fetch_profile(username)
    player_id = profile["player_id"].to_s
    if player_id.blank?
      redirect_to beta_sources_chess_path, alert: t("flash.chess.profile_invalid")
      return
    end

    taken = User.where(chess_com_player_id: player_id).where.not(id: current_user.id).exists?
    if taken
      redirect_to beta_sources_chess_path, alert: t("flash.chess.account_already_linked")
      return
    end

    # Keep the same code while pending for this username so Location paste stays valid.
    reuse_code =
      current_user.chess_com_verification_pending? &&
      current_user.chess_com_username == username &&
      current_user.chess_com_verification_code.present?

    code = reuse_code ? current_user.chess_com_verification_code : ChessComService.generate_verification_code
    expires_at =
      if reuse_code && current_user.chess_com_verification_code_expires_at&.future?
        current_user.chess_com_verification_code_expires_at
      else
        ChessComService::VERIFICATION_CODE_TTL.from_now
      end

    current_user.update!(
      chess_com_username: username,
      chess_com_player_id: nil,
      chess_com_verified_at: nil,
      chess_com_verification_code: code,
      chess_com_verification_code_expires_at: expires_at
    )

    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: "chess_com_link_started",
      properties: { username: username, code_reused: reuse_code }
    )
    redirect_to beta_sources_chess_path, notice: t("flash.chess.link_started", code: code)
  rescue ChessComService::NotFound
    redirect_to beta_sources_chess_path, alert: t("flash.chess.username_not_found")
  rescue ChessComService::Error => e
    redirect_to beta_sources_chess_path, alert: t("flash.chess.error", message: e.message)
  end

  def verify
    unless current_user.chess_com_verification_pending?
      redirect_to beta_sources_chess_path, alert: t("flash.chess.verification_not_pending")
      return
    end

    code = current_user.chess_com_verification_code
    username = current_user.chess_com_username
    profile = ChessComService.new.verify_location!(username, code)
    player_id = profile["player_id"].to_s

    taken = User.where(chess_com_player_id: player_id).where.not(id: current_user.id).exists?
    if taken
      redirect_to beta_sources_chess_path, alert: t("flash.chess.account_already_linked")
      return
    end

    current_user.update!(
      chess_com_player_id: player_id,
      chess_com_verified_at: Time.current,
      chess_com_verification_code: nil,
      chess_com_verification_code_expires_at: nil
    )

    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: "chess_com_verified",
      properties: { username: username, player_id: player_id }
    )
    redirect_to beta_sources_chess_path, notice: t("flash.chess.verified", username: username)
  rescue ChessComService::Error => e
    redirect_to beta_sources_chess_path, alert: t("flash.chess.verify_failed", message: e.message)
  end

  def disconnect
    current_user.chess_com_goals.find_each do |goal|
      current_user.chess_com_config&.remove_scenarios_for_goal!(goal.id)
    end
    current_user.chess_com_goals.destroy_all
    current_user.chess_com_config&.destroy
    current_user.update!(
      chess_com_username: nil,
      chess_com_player_id: nil,
      chess_com_verified_at: nil,
      chess_com_verification_code: nil,
      chess_com_verification_code_expires_at: nil
    )

    PostHog.capture(distinct_id: current_user.posthog_distinct_id, event: "chess_com_disconnected")
    redirect_to beta_sources_chess_path, notice: t("flash.chess.disconnected")
  end

  def create_goal
    goal = current_user.chess_com_goals.new(goal_params)
    goal.baseline_rating = ChessComService.new.current_rating_for!(
      current_user.chess_com_username,
      goal.rating_type
    )
    goal.save!
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: "chess_com_goal_created",
      properties: {
        goal_name: goal.name,
        rating_type: goal.rating_type,
        target_rating: goal.target_rating
      }
    )
    PosthogProductAnalytics.configured_source(current_user, name: "chess")
    redirect_to beta_chess_goal_show_path(goal), notice: t("flash.chess.goal_created", name: goal.name)
  rescue ChessComService::RatingUnavailable => e
    redirect_to beta_sources_chess_path, alert: t("flash.chess.rating_unavailable", message: e.message)
  rescue ChessComService::Error => e
    redirect_to beta_sources_chess_path, alert: t("flash.chess.error", message: e.message)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_chess_path, alert: e.record.errors.full_messages.join(", ")
  end

  def update_goal
    @goal.assign_attributes(goal_params)
    @goal.save!
    PosthogProductAnalytics.configured_source(current_user, name: "chess")
    redirect_to beta_chess_goal_show_path(@goal), notice: t("flash.chess.goal_updated", name: @goal.name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_chess_goal_show_path(@goal), alert: e.record.errors.full_messages.join(", ")
  end

  def destroy_goal
    name = @goal.name
    goal_id = @goal.id
    @goal.destroy!
    current_user.chess_com_config&.remove_scenarios_for_goal!(goal_id)
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: "chess_com_goal_destroyed",
      properties: { goal_name: name }
    )
    redirect_to beta_sources_chess_path, notice: t("flash.chess.goal_destroyed", name: name)
  end

  def check_goal
    check = ChessComGoalEvaluator.new(current_user).evaluate_goal!(@goal, due_at: @goal.manual_check_due_at)
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: "chess_com_goal_checked",
      properties: {
        goal_name: @goal.name,
        status: check.status,
        rating_at_check: check.rating_at_check,
        target_rating: check.target_rating
      }
    )
    redirect_to beta_chess_goal_show_path(@goal), notice: chess_check_notice(check)
  rescue ChessComService::Error, ChasterService::Error => e
    redirect_to beta_chess_goal_show_path(@goal), alert: t("flash.chess.check_impossible", message: e.message)
  end

  def preview_check
    preview = ChessComGoalEvaluator.new(current_user).preview_goal(@goal, due_at: @goal.preview_check_due_at)
    flash[:chess_preview] = {
      status: preview[:status],
      rating_at_check: preview[:rating_at_check],
      target_rating: preview[:target_rating],
      baseline_rating: preview[:baseline_rating],
      rating_type: preview[:rating_type],
      due_at: preview[:due_at].iso8601
    }
    redirect_to beta_chess_goal_show_path(@goal)
  rescue ChessComService::Error => e
    redirect_to beta_chess_goal_show_path(@goal), alert: t("flash.chess.check_impossible", message: e.message)
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.chess.beta_only")
  end

  def require_chess_platform_enabled!
    return if BetaCatalog.new(current_user).source_platform_enabled?("chess")

    redirect_to beta_dashboard_path, alert: t("flash.chess.platform_disabled")
  end

  def require_chess_com_verified!
    return if current_user.reload.chess_com_verified?

    redirect_to beta_sources_chess_path, alert: t("flash.chess.verify_first")
  end

  def set_goal
    @goal = current_user.chess_com_goals.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_sources_chess_path, alert: t("flash.chess.goal_not_found")
  end

  def goal_params
    prefix = goal_form_field_prefix
    p = params.permit(
      :name, :enabled, :rating_type, :target_rating, :deadline_at,
      :"#{prefix}_schedule_mode",
      :"#{prefix}_recurrence_kind",
      :"#{prefix}_check_time",
      :"#{prefix}_interval_minutes"
    )
    zone_name = current_user.effective_time_zone
    schedule_mode = p[:"#{prefix}_schedule_mode"].to_s.presence_in(ChessComGoal::SCHEDULE_MODES) || "deadline"
    recurring = schedule_mode == "recurring"
    recurrence_kind =
      if recurring
        p[:"#{prefix}_recurrence_kind"].to_s.presence_in(ChessComGoal::RECURRENCE_KINDS) || "daily"
      else
        "daily"
      end
    check_time_minutes =
      recurring && recurrence_kind == "daily" ? check_time_minutes_param(p[:"#{prefix}_check_time"]) : nil
    interval_minutes =
      recurring && recurrence_kind == "interval" ? positive_interval_minutes(p[:"#{prefix}_interval_minutes"]) : nil
    deadline = parse_deadline(p[:deadline_at], zone_name)

    {
      name: p[:name].to_s.strip,
      enabled: p[:enabled] == "1",
      rating_type: p[:rating_type].presence || "blitz",
      target_rating: p[:target_rating].to_i,
      schedule_mode: schedule_mode,
      recurrence_kind: recurrence_kind,
      check_time_minutes: check_time_minutes,
      interval_minutes: interval_minutes,
      deadline_at: deadline,
      time_zone: zone_name
    }
  end

  def goal_form_field_prefix
    case action_name
    when "create_goal" then "new_chess_goal"
    else "chess_goal_#{@goal.id}"
    end
  end

  def check_time_minutes_param(value)
    hours, minutes = value.to_s.split(":", 2).map(&:to_i)
    minutes ||= 0
    return 0 unless hours.between?(0, 23) && minutes.between?(0, 59)

    hours * 60 + minutes
  end

  def positive_interval_minutes(value)
    minutes = value.to_i
    return nil unless minutes.between?(ChessComGoal::MIN_INTERVAL_MINUTES, ChessComGoal::MAX_INTERVAL_MINUTES)

    minutes
  end

  def parse_deadline(value, time_zone)
    return nil if value.blank?

    zone = ActiveSupport::TimeZone[time_zone.presence || current_user.effective_time_zone] || Time.zone
    zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def chess_check_notice(check)
    case check.status
    when "passed"
      t(
        "flash.chess.check_passed",
        rating: check.rating_at_check,
        target: check.target_rating
      )
    when "failed"
      t(
        "flash.chess.check_failed",
        rating: check.rating_at_check || "—",
        target: check.target_rating
      )
    else
      t(
        "flash.chess.check_chaster_failed",
        rating: check.rating_at_check || "—",
        target: check.target_rating,
        chaster_error: check.chaster_error.to_s
      )
    end
  end
end
