# frozen_string_literal: true

class CornertimeViolationRecorder
  Result = Struct.new(
    :ok,
    :violation,
    :status,
    :cooldown_remaining_seconds,
    :actions_executed,
    :error,
    :http_status,
    keyword_init: true
  )

  def initialize(session:, motion_score: nil, detected_at: nil, client_violation_id: nil)
    @session = session
    @user = session.user
    @motion_score = motion_score
    @detected_at = detected_at || Time.current
    @client_violation_id = client_violation_id.presence
  end

  def call
    if @client_violation_id.present?
      existing = @session.cornertime_violations.find_by(client_violation_id: @client_violation_id)
      if existing
        return Result.new(
          ok: true,
          violation: existing,
          status: existing.status,
          actions_executed: existing.actions_executed,
          cooldown_remaining_seconds: 0
        )
      end
    end

    unless @session.open?
      return Result.new(
        ok: false,
        error: I18n.t("cornertime.errors.session_not_active"),
        http_status: :unprocessable_entity
      )
    end

    @session.mark_active!

    unless BetaCatalog.new(@user).source_enabled?("cornertime")
      violation = create_violation!(status: "source_disabled", actions: [])
      return Result.new(
        ok: false,
        violation: violation,
        status: "source_disabled",
        error: I18n.t("cornertime.errors.source_disabled"),
        http_status: :unprocessable_entity
      )
    end

    config = @user.ensure_cornertime_config!
    last_applied = @session.cornertime_violations.applied.order(detected_at: :desc).first
    if last_applied
      elapsed = (@detected_at - last_applied.detected_at).to_i
      remaining = config.violation_cooldown_seconds - elapsed
      if remaining.positive?
        violation = create_violation!(status: "cooldown_skipped", actions: [])
        return Result.new(
          ok: true,
          violation: violation,
          status: "cooldown_skipped",
          cooldown_remaining_seconds: remaining,
          actions_executed: []
        )
      end
    end

    sanction = config.movement_sanction_object
    unless sanction.any_active?
      violation = create_violation!(status: "no_sanctions", actions: [])
      @session.increment!(:violation_count)
      return Result.new(
        ok: true,
        violation: violation,
        status: "no_sanctions",
        cooldown_remaining_seconds: config.violation_cooldown_seconds,
        actions_executed: []
      )
    end

    actions = BetaEvents::SanctionApplier.new(
      beta: @user,
      source: :cornertime,
      kind_map: CornertimeConfig.kind_map_for(:movement_detected)
    ).apply!(
      sanction,
      metadata: {
        "session_id" => @session.id,
        "motion_score" => @motion_score
      }.compact
    )

    violation = create_violation!(status: "applied", actions: actions)
    @session.increment!(:violation_count)

    Result.new(
      ok: true,
      violation: violation,
      status: "applied",
      cooldown_remaining_seconds: config.violation_cooldown_seconds,
      actions_executed: actions
    )
  rescue StandardError => e
    Rails.logger.error("[CornertimeViolationRecorder] #{e.class}: #{e.message}")
    violation = create_violation!(status: "error", actions: [{ "error" => e.message }])
    Result.new(
      ok: false,
      violation: violation,
      status: "error",
      error: I18n.t("cornertime.errors.action_failed"),
      http_status: :unprocessable_entity
    )
  end

  private

  def create_violation!(status:, actions:)
    @session.cornertime_violations.create!(
      detected_at: @detected_at,
      motion_score: @motion_score,
      client_violation_id: @client_violation_id,
      actions_executed: actions,
      status: status
    )
  end
end
