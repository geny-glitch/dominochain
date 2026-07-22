# frozen_string_literal: true

class ChessComGoalEvaluator
  def initialize(user, chess_com_service: ChessComService.new(user), chaster_service: ChasterService.new(user))
    @user = user
    @chess_com_service = chess_com_service
    @chaster_service = chaster_service
  end

  def evaluate_goal!(goal, due_at: nil)
    due_at ||= goal.manual_check_due_at
    due_at = normalize_due_at(goal, due_at)
    existing = goal.chess_com_goal_checks.find_by(due_at: due_at)
    return existing if existing

    rating_at_check = nil
    status = nil
    chaster_applied = false
    chaster_error = nil
    chaster_lock_id = nil
    sanctions_applied = []

    begin
      rating_at_check = @chess_com_service.current_rating_for!(@user.chess_com_username, goal.rating_type)
      status = rating_at_check >= goal.target_rating ? "passed" : "failed"
    rescue ChessComService::RatingUnavailable => e
      rating_at_check = nil
      status = "failed"
      chaster_error = e.message.to_s.truncate(500)
    end

    if status == "failed"
      result = apply_failure_consequences!(
        goal: goal,
        due_at: due_at,
        rating_at_check: rating_at_check,
        status_holder: ->(value) { status = value },
        applied_holder: ->(value) { chaster_applied = value },
        error_holder: ->(value) { chaster_error = value },
        lock_holder: ->(value) { chaster_lock_id = value }
      )
      sanctions_applied.concat(result)
    end
  rescue ChasterService::Unauthorized
    status = "chaster_error"
    chaster_error = "Chaster non connecté"
  rescue ChasterService::Error => e
    status = "chaster_error"
    chaster_error = e.message.to_s.truncate(500)
  ensure
    if status.present?
      check = create_check!(
        goal,
        due_at: due_at,
        rating_at_check: rating_at_check,
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
    @user.chess_com_goals.enabled.order(:id).filter_map do |goal|
      evaluate_due_goal!(goal, now: now)
    end
  end

  def evaluate_due_goal!(goal, now: Time.current)
    if goal.interval_recurring?
      last_check = nil
      loop do
        due_at = goal.due_at_or_before(now)
        break unless due_at

        last_check = evaluate_goal!(goal, due_at: due_at)
        goal.reload
        break if goal.achieved?
      end
      last_check
    else
      due_at = goal.due_at_or_before(now)
      return unless due_at

      evaluate_goal!(goal, due_at: due_at)
    end
  end

  def preview_goal(goal, due_at: nil)
    due_at ||= goal.preview_check_due_at
    due_at = normalize_due_at(goal, due_at)
    rating_at_check = @chess_com_service.current_rating_for!(@user.chess_com_username, goal.rating_type)

    {
      due_at: due_at,
      target_rating: goal.target_rating,
      baseline_rating: goal.baseline_rating,
      rating_at_check: rating_at_check,
      rating_type: goal.rating_type,
      status: rating_at_check >= goal.target_rating ? "passed" : "failed"
    }
  end

  private

  def apply_failure_consequences!(goal:, due_at:, rating_at_check:, status_holder:, applied_holder:, error_holder:, lock_holder:)
    config = @user.chess_com_config || @user.ensure_chess_com_config!
    scenarios = config.scenario_set.scenarios_for_goal_failure(goal)

    all_rows = []
    scenarios.each do |scenario|
      sanction = scenario.to_sanction_set
      next unless sanction.any_active?

      rows = apply_sanction_set!(
        sanction: sanction,
        goal: goal,
        due_at: due_at,
        rating_at_check: rating_at_check,
        status_holder: status_holder,
        applied_holder: applied_holder,
        error_holder: error_holder,
        lock_holder: lock_holder
      )
      all_rows.concat(rows)
    end
    all_rows
  end

  def apply_sanction_set!(sanction:, goal:, due_at:, rating_at_check:, status_holder:, applied_holder:, error_holder:, lock_holder:)
    kind_map = {
      "chaster.add_time" => :failed_penalty,
      "leverage_photo.lock" => :failed_penalty,
      "leverage_photo.delete" => :failed_penalty
    }

    rows = BetaEvents::SanctionApplier.new(
      beta: @user,
      source: :chess_com_goal,
      kind_map: kind_map,
      execute: lambda { |event, _context|
        enriched = BetaEvents::DomainEvent.new(
          beta: @user,
          source: event.source,
          kind: event.kind,
          payload: event.payload.merge(
            goal_id: goal.id,
            goal_title: goal.name,
            due_at: due_at.iso8601,
            rating_type: goal.rating_type,
            target_rating: goal.target_rating,
            rating_at_check: rating_at_check
          )
        )
        begin
          status = BetaEvents::ActionExecutor.new(beta: @user, event: enriched).call
          status.to_s
        rescue BetaEvents::ActionExecutionStopped => e
          if enriched[:possibility_id].to_s == "chaster.add_time"
            status_holder.call("chaster_error")
            applied_holder.call(false)
            lock_holder.call(nil)
            error_holder.call(chaster_stop_message(e))
          end
          "stopped:#{e.reason}"
        end
      }
    ).apply!(sanction)

    chaster_row = rows.find { |row| row["possibility_id"].to_s == "chaster.add_time" }
    if chaster_row
      result = chaster_row["result"].to_s
      if result == "ok" || result == "applied"
        applied_holder.call(true)
        lock = @chaster_service.current_lock
        lock_holder.call(lock&.dig(:id))
      elsif !result.start_with?("stopped:")
        applied_holder.call(false)
        lock_holder.call(nil)
        error_holder.call("Source ou action désactivée.")
      end
    end

    rows.map do |row|
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

  def chaster_stop_message(error)
    case error.reason
    when :no_chaster_lock then "Aucun cadenas Chaster actif."
    when :chaster_unauthorized then "Chaster non connecté"
    when :chaster_error, :missing_seconds then (error.detail.presence || "Erreur Chaster")
    else (error.detail.presence || "Erreur Chaster")
    end
  end

  def normalize_due_at(goal, due_at)
    raise ArgumentError, "missing due_at" if due_at.blank?

    zone = goal.time_zone_object
    due_at.in_time_zone(zone).change(sec: 0).utc
  end

  def create_check!(goal, due_at:, rating_at_check:, status:, chaster_applied:, chaster_error:, chaster_lock_id:, sanctions_applied: [])
    details = {
      rating_type: goal.rating_type,
      target_rating: goal.target_rating,
      baseline_rating: goal.baseline_rating,
      rating_at_check: rating_at_check,
      deadline_at: goal.deadline_at.iso8601,
      time_zone: goal.time_zone,
      sanctions_applied: sanctions_applied
    }

    goal.chess_com_goal_checks.create!(
      user: @user,
      due_at: due_at,
      rating_type: goal.rating_type,
      target_rating: goal.target_rating,
      baseline_rating: goal.baseline_rating,
      rating_at_check: rating_at_check,
      status: status,
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
      last_check_rating: check.rating_at_check,
      last_check_target_rating: check.target_rating,
      last_check_status: check.status,
      last_check_chaster_applied: check.chaster_applied,
      last_check_chaster_error: check.chaster_error,
      last_check_details: check.details,
      updated_at: Time.current
    )
  end
end
