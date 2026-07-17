# frozen_string_literal: true

class StravaGoalEvaluator
  def initialize(user, strava_service: StravaService.new(user), chaster_service: ChasterService.new(user))
    @user = user
    @strava_service = strava_service
    @chaster_service = chaster_service
  end

  def evaluate_goal!(goal, due_at: goal.previous_due_at)
    due_at = normalize_due_at(goal, due_at)
    existing = goal.strava_goal_checks.find_by(due_at: due_at)
    return existing if existing

    period_start_at = goal.period_start_for(due_at)
    period_end_at = due_at
    activities = activities_for_period(period_start_at, period_end_at, include_details: detailed_activities_required?([ goal ]))
    matching = activities.select { |activity| activity_matches_goal?(activity, goal) }
    status = matching.count >= goal.required_count ? "passed" : "failed"
    chaster_applied = false
    chaster_error = nil
    chaster_lock_id = nil
    sanctions_applied = []

    if status == "failed"
      apply_chaster_penalty!(
        goal: goal,
        due_at: due_at,
        status_holder: ->(value) { status = value },
        applied_holder: ->(value) { chaster_applied = value },
        error_holder: ->(value) { chaster_error = value },
        lock_holder: ->(value) { chaster_lock_id = value }
      )
      sanctions_applied.concat(apply_leverage_sanctions!(goal: goal, due_at: due_at))
    end
  rescue ChasterService::Unauthorized
    status = "chaster_error"
    chaster_error = "Chaster non connecté"
  rescue ChasterService::Error => e
    status = "chaster_error"
    chaster_error = e.message.to_s.truncate(500)
  ensure
    if defined?(activities) && defined?(matching) && status.present?
      check = create_check!(
        goal,
        due_at: due_at,
        period_start_at: period_start_at,
        period_end_at: period_end_at,
        activities: activities,
        matching: matching,
        status: status,
        chaster_applied: chaster_applied,
        chaster_error: chaster_error,
        chaster_lock_id: chaster_lock_id,
        sanctions_applied: sanctions_applied
      )
      sync_goal_last_check!(goal, check)
      return check
    end
  end

  def evaluate_due_goals!(now: Time.current)
    @user.strava_goals.enabled.order(:id).filter_map do |goal|
      due_at = goal.due_at_or_before(now)
      next unless due_at

      evaluate_goal!(goal, due_at: due_at)
    end
  end

  def preview_goal(goal, due_at: Time.current)
    due_at = normalize_due_at(goal, due_at)
    period_start_at = goal.period_start_for(due_at)
    activities = activities_for_period(period_start_at, due_at, include_details: detailed_activities_required?([ goal ]))
    matching = activities.select { |activity| activity_matches_goal?(activity, goal) }

    {
      due_at: due_at,
      period_start_at: period_start_at,
      period_end_at: due_at,
      required_count: goal.required_count,
      valid_count: matching.count,
      total_count: activities.count,
      activity_ids: activities.map { |activity| activity[:id] },
      matching_activity_ids: matching.map { |activity| activity[:id] }
    }
  end

  private

  def apply_chaster_penalty!(goal:, due_at:, status_holder:, applied_holder:, error_holder:, lock_holder:)
    event = BetaEvents::DomainEvent.new(
      beta: @user,
      source: :strava_goal,
      kind: :failed_penalty,
      payload: {
        possibility_id: "chaster.add_time",
        seconds: goal.chaster_penalty_seconds,
        goal_id: goal.id,
        goal_title: goal.name,
        due_at: due_at.iso8601
      }
    )
    begin
      execution_status = BetaEvents::ActionExecutor.new(beta: @user, event: event).call
      if execution_status == :ok
        applied_holder.call(true)
        lock = @chaster_service.current_lock
        lock_holder.call(lock&.dig(:id))
      else
        applied_holder.call(false)
        lock_holder.call(nil)
        error_holder.call("Source ou action désactivée.")
      end
    rescue BetaEvents::ActionExecutionStopped => e
      status_holder.call("chaster_error")
      applied_holder.call(false)
      lock_holder.call(nil)
      error_holder.call(chaster_stop_message(e))
    end
  end

  def chaster_stop_message(error)
    case error.reason
    when :no_chaster_lock then "Aucun cadenas Chaster actif."
    when :chaster_unauthorized then "Chaster non connecté"
    when :chaster_error, :missing_seconds then (error.detail.presence || "Erreur Chaster")
    else (error.detail.presence || "Erreur Chaster")
    end
  end

  def apply_leverage_sanctions!(goal:, due_at:)
    sanction = goal.failure_sanction_object
    return [] unless sanction.any_active?

    kind_map = {
      "leverage_photo.lock" => :failed_penalty,
      "leverage_photo.delete" => :failed_penalty
    }

    applier = BetaEvents::SanctionApplier.new(
      beta: @user,
      source: :strava_goal,
      kind_map: kind_map,
      execute: lambda { |event, context|
        # Enrich payload with goal metadata for audit/descriptions.
        enriched = BetaEvents::DomainEvent.new(
          beta: @user,
          source: event.source,
          kind: event.kind,
          payload: event.payload.merge(
            goal_id: goal.id,
            goal_title: goal.name,
            due_at: due_at.iso8601,
            source: "strava"
          )
        )
        begin
          status = BetaEvents::ActionExecutor.new(beta: @user, event: enriched, context: context).call
          status.to_s
        rescue BetaEvents::ActionExecutionStopped => e
          "stopped:#{e.reason}"
        end
      }
    )

    applier.apply!(sanction).map do |row|
      {
        "action" => row["action"],
        "possibility_id" => row["possibility_id"],
        "status" => row["result"].to_s,
        "target_mode" => row["target_mode"],
        "photo_id" => row["leverage_photo_id"],
        "seconds" => row["seconds"]
      }.compact
    end
  end

  def normalize_due_at(goal, due_at)
    zone = goal.time_zone_object
    due_at.in_time_zone(zone).change(sec: 0).utc
  end

  def activities_for_period(period_start_at, period_end_at, include_details:)
    @strava_service.activities_between(start_time: period_start_at, end_time: period_end_at, include_details: include_details)
  end

  def detailed_activities_required?(goals)
    Array(goals).any? { |goal| goal.min_calories.present? || goal.device_names.present? }
  end

  def activity_matches_goal?(activity, goal)
    return false if goal.min_duration_seconds.present? && activity[:duration_seconds].to_i < goal.min_duration_seconds
    return false if goal.min_calories.present? && activity[:calories].to_i < goal.min_calories
    return false if goal.activity_types.present? && (goal.activity_types & activity_types_for(activity)).empty?
    return false if goal.device_names.present? && !device_matches?(activity[:device_name], goal.device_names)

    true
  end

  def activity_types_for(activity)
    [ activity[:type], activity[:sport_type] ].compact.map(&:to_s)
  end

  def device_matches?(activity_device_name, expected_device_names)
    name = activity_device_name.to_s.downcase
    return false if name.blank?

    expected_device_names.any? { |expected| name.include?(expected.to_s.downcase) }
  end

  def create_check!(goal, due_at:, period_start_at:, period_end_at:, activities:, matching:, status:, chaster_applied:, chaster_error:, chaster_lock_id:, sanctions_applied: [])
    details = {
      activity_ids: activities.map { |activity| activity[:id] },
      matching_activity_ids: matching.map { |activity| activity[:id] },
      criteria: {
        min_duration_seconds: goal.min_duration_seconds,
        min_calories: goal.min_calories,
        activity_types: goal.activity_types,
        device_names: goal.device_names
      },
      window: {
        days: goal.window_days,
        check_time: goal.check_time_label,
        time_zone: goal.time_zone
      },
      sanctions_applied: sanctions_applied
    }

    goal.strava_goal_checks.create!(
      user: @user,
      due_at: due_at,
      period_start_at: period_start_at,
      period_end_at: period_end_at,
      window_days: goal.window_days,
      check_time_minutes: goal.check_time_minutes,
      time_zone: goal.time_zone,
      required_count: goal.required_count,
      valid_count: matching.count,
      total_count: activities.count,
      status: status,
      chaster_penalty_seconds: goal.chaster_penalty_seconds,
      chaster_lock_id: chaster_lock_id,
      chaster_applied: chaster_applied,
      chaster_error: chaster_error,
      details: details,
      checked_at: Time.current
    )
  end

  def sync_goal_last_check!(goal, check)
    goal.update_columns(
      last_check_due_at: check.due_at,
      last_check_period_start_at: check.period_start_at,
      last_check_period_end_at: check.period_end_at,
      last_check_valid_count: check.valid_count,
      last_check_total_count: check.total_count,
      last_check_status: check.status,
      last_check_chaster_applied: check.chaster_applied,
      last_check_chaster_error: check.chaster_error,
      last_check_details: check.details,
      updated_at: Time.current
    )
  end
end
