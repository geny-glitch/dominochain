# frozen_string_literal: true

class StravaGoalEvaluator
  def self.previous_week_start_on
    Date.current.beginning_of_week(:monday) - 1.week
  end

  def initialize(user, strava_service: StravaService.new(user), chaster_service: ChasterService.new(user))
    @user = user
    @strava_service = strava_service
    @chaster_service = chaster_service
  end

  def evaluate_goal!(goal, week_start_on: self.class.previous_week_start_on)
    week_start_on = week_start_on.to_date
    week_end_on = week_start_on + 6.days
    existing = goal.strava_goal_checks.find_by(week_start_on: week_start_on)
    return existing if existing

    activities = activities_for_week(week_start_on, include_details: goal.min_calories.present? || goal.device_names.present?)
    matching = activities.select { |activity| activity_matches_goal?(activity, goal) }
    status = matching.count >= goal.weekly_required_count ? "passed" : "failed"
    chaster_applied = false
    chaster_error = nil
    chaster_lock_id = nil

    if status == "failed"
      lock = @chaster_service.current_lock
      if lock&.dig(:id).present?
        chaster_lock_id = lock[:id]
        @chaster_service.add_time_to_lock(lock[:id], goal.chaster_penalty_seconds)
        chaster_applied = true
      else
        status = "chaster_error"
        chaster_error = "Aucun cadenas Chaster actif."
      end
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
        week_start_on: week_start_on,
        week_end_on: week_end_on,
        activities: activities,
        matching: matching,
        status: status,
        chaster_applied: chaster_applied,
        chaster_error: chaster_error,
        chaster_lock_id: chaster_lock_id
      )
      sync_goal_last_check!(goal, check)
      return check
    end
  end

  def evaluate_enabled_goals!(week_start_on: self.class.previous_week_start_on)
    @user.strava_goals.enabled.order(:id).map do |goal|
      evaluate_goal!(goal, week_start_on: week_start_on)
    end
  end

  def preview_goal(goal, week_start_on: Date.current.beginning_of_week(:monday))
    week_start_on = week_start_on.to_date
    activities = activities_for_week(week_start_on, include_details: detailed_activities_required?([goal]))
    matching = activities.select { |activity| activity_matches_goal?(activity, goal) }

    {
      week_start_on: week_start_on,
      week_end_on: [week_start_on + 6.days, Date.current].min,
      required_count: goal.weekly_required_count,
      valid_count: matching.count,
      total_count: activities.count,
      activity_ids: activities.map { |activity| activity[:id] },
      matching_activity_ids: matching.map { |activity| activity[:id] }
    }
  end

  private

  def activities_for_week(week_start_on, include_details:)
    after = week_start_on.beginning_of_day
    before = (week_start_on + 1.week).beginning_of_day
    @strava_service.activities_between(start_time: after, end_time: before, include_details: include_details)
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
    [activity[:type], activity[:sport_type]].compact.map(&:to_s)
  end

  def device_matches?(activity_device_name, expected_device_names)
    name = activity_device_name.to_s.downcase
    return false if name.blank?

    expected_device_names.any? { |expected| name.include?(expected.to_s.downcase) }
  end

  def create_check!(goal, week_start_on:, week_end_on:, activities:, matching:, status:, chaster_applied:, chaster_error:, chaster_lock_id:)
    details = {
      activity_ids: activities.map { |activity| activity[:id] },
      matching_activity_ids: matching.map { |activity| activity[:id] },
      criteria: {
        min_duration_seconds: goal.min_duration_seconds,
        min_calories: goal.min_calories,
        activity_types: goal.activity_types,
        device_names: goal.device_names
      }
    }

    goal.strava_goal_checks.create!(
      user: @user,
      week_start_on: week_start_on,
      week_end_on: week_end_on,
      required_count: goal.weekly_required_count,
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
      last_checked_week_start_on: check.week_start_on,
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
