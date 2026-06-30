# frozen_string_literal: true

class WallpaperEnforcementEvaluator
  def initialize(user, chaster_service: ChasterService.new(user))
    @user = user
    @chaster_service = chaster_service
  end

  def evaluate_scheduled_check!(device:, reference_time: Time.current)
    config = @user.wallpaper_enforcement_config
    return unless config&.enabled?

    sanctions = []
    status = nil
    details = {}

    unless device.permissions_ok != false && device.permissions_missing_list.empty?
      status = "permissions_missing"
      sanctions.concat(apply_permissions_lost_sanction!(config, device, reference_time))
    end

    unless device.reachable?(threshold_minutes: config.app_unreachable_threshold_minutes, reference_time: reference_time)
      if status.blank?
        status = "app_unreachable"
        sanctions.concat(apply_app_unreachable_sanction!(config, device, reference_time))
      end
      details["last_seen_at"] = device.last_seen_at&.iso8601
    end

    if status.present?
      create_check!(
        device: device,
        status: status,
        check_kind: status == "permissions_missing" ? "permissions" : "app_unreachable",
        sanctions_applied: sanctions,
        details: details,
        reference_time: reference_time
      )
    end

    config.update!(last_scheduled_check_at: reference_time)
    if device.reachable?(threshold_minutes: config.app_unreachable_threshold_minutes, reference_time: reference_time)
      config.update!(app_unreachable_sanction_applied_at: nil) if config.app_unreachable_sanction_applied_at.present?
    end
    request_screenshot_if_due!(device, config, reference_time)
  end

  def evaluate_verification!(screenshot:, reference_time: Time.current)
    config = @user.wallpaper_enforcement_config
    return unless config&.enabled?

    device = screenshot.device
    verification_status = screenshot.verification_status
    sanctions = []
    status = verification_status
    details = { "verification_status" => verification_status }

    case verification_status
    when "verified"
      sanctions.concat(handle_verified!(config, reference_time))
    when "mismatch"
      sanctions.concat(handle_mismatch!(config, reference_time))
    when "inconclusive", "skipped", "pending"
      status = verification_status == "pending" ? "pending_screenshot" : verification_status
    end

    create_check!(
      device: device,
      status: status,
      check_kind: "scheduled",
      device_screenshot: screenshot,
      similarity_score: screenshot.similarity_score,
      sanctions_applied: sanctions,
      details: details,
      reference_time: reference_time
    )
  end

  def reset_mismatch_on_wallpaper_change!
    config = @user.wallpaper_enforcement_config
    return unless config

    config.reset_mismatch_state!
    unfreeze_if_needed!(config)
  end

  private

  def request_screenshot_if_due!(device, config, reference_time)
    return unless device.fcm_token.present?

    FcmService.send_take_screenshot_notification(
      device: device,
      dismiss_apps: config.dismiss_apps_before_capture
    )
  end

  def handle_verified!(config, reference_time)
    sanctions = []
    config.reset_mismatch_state!
    if config.frozen_by_enforcement?
      sanctions.concat(unfreeze_if_needed!(config))
    end
    sanctions
  end

  def handle_mismatch!(config, reference_time)
    sanctions = []
    config.mismatch_since ||= reference_time
    config.save! if config.changed?

    mismatch_duration = reference_time - config.mismatch_since

    if should_apply_add_time_sanction?(config, mismatch_duration, reference_time)
      sanctions.concat(apply_sanction!(
        config: config,
        sanction: config.mismatch_add_time_sanction_object,
        kind: :mismatch_add_time,
        reference_time: reference_time
      ))
      config.update!(add_time_sanction_applied_at: reference_time)
    end

    if should_apply_freeze_sanction?(config, mismatch_duration)
      sanction = config.mismatch_freeze_sanction_object
      if sanction.action == "chaster_freeze" && !config.frozen_by_enforcement?
        sanctions.concat(apply_sanction!(
          config: config,
          sanction: sanction,
          kind: :mismatch_freeze,
          reference_time: reference_time
        ))
        config.update!(frozen_by_enforcement: true)
      end
    end

    sanctions
  end

  def should_apply_add_time_sanction?(config, mismatch_duration, reference_time)
    return false unless config.mismatch_add_time_sanction_object.active?
    return false if config.add_time_sanction_applied_at.present?

    mismatch_duration >= config.mismatch_add_time_delay_minutes.minutes
  end

  def should_apply_freeze_sanction?(config, mismatch_duration)
    return false unless config.mismatch_freeze_sanction_object.action == "chaster_freeze"
    return false if config.frozen_by_enforcement?

    mismatch_duration >= config.mismatch_freeze_delay_minutes.minutes
  end

  def apply_permissions_lost_sanction!(config, device, reference_time)
    return [] unless config.permissions_lost_sanction_object.active?
    return [] if config.permissions_lost_sanction_applied_at.present? &&
      config.last_permissions_ok_at.present? &&
      config.permissions_lost_sanction_applied_at >= config.last_permissions_ok_at

    sanctions = apply_sanction!(
      config: config,
      sanction: config.permissions_lost_sanction_object,
      kind: :permissions_lost,
      reference_time: reference_time,
      details: { "permissions_missing" => device.permissions_missing_list }
    )
    config.update!(permissions_lost_sanction_applied_at: reference_time)
    sanctions
  end

  def apply_app_unreachable_sanction!(config, device, reference_time)
    return [] unless config.app_unreachable_sanction_object.active?
    return [] if config.app_unreachable_sanction_applied_at.present? &&
      device.last_seen_at.present? &&
      config.app_unreachable_sanction_applied_at >= device.last_seen_at

    sanctions = apply_sanction!(
      config: config,
      sanction: config.app_unreachable_sanction_object,
      kind: :app_unreachable,
      reference_time: reference_time,
      details: { "last_seen_at" => device.last_seen_at&.iso8601 }
    )
    config.update!(app_unreachable_sanction_applied_at: reference_time)
    sanctions
  end

  def apply_sanction!(config:, sanction:, kind:, reference_time:, details: {})
    return [] unless sanction.active?

    event = build_event(kind: kind, sanction: sanction, details: details)
    result = execute_event(event)
    [
      {
        "kind" => kind.to_s,
        "action" => sanction.action,
        "result" => result,
        "applied_at" => reference_time.iso8601
      }
    ]
  end

  def unfreeze_if_needed!(config)
    return [] unless config.frozen_by_enforcement?

    event = BetaEvents::DomainEvent.new(
      beta: @user,
      source: :wallpaper,
      kind: :enforcement_unfreeze,
      payload: {
        action: "chaster_freeze",
        source: "wallpaper",
        summary: "Wallpaper compliance restored"
      }
    )
    result = execute_event(event)
    config.update!(frozen_by_enforcement: false)
    [
      {
        "kind" => "enforcement_unfreeze",
        "action" => "chaster_freeze",
        "result" => result,
        "applied_at" => Time.current.iso8601
      }
    ]
  end

  def build_event(kind:, sanction:, details: {})
    payload = {
      action: sanction.action,
      source: "wallpaper",
      summary: "Wallpaper enforcement: #{kind.to_s.tr('_', ' ')}",
      metadata: details
    }

    case sanction.action
    when "chaster_add_time"
      payload[:seconds] = sanction.chaster_seconds
    when "pishock"
      payload[:pishock_intensity] = sanction.pishock_intensity
      payload[:pishock_duration] = sanction.pishock_duration
    end

    BetaEvents::DomainEvent.new(
      beta: @user,
      source: :wallpaper,
      kind: kind,
      payload: payload
    )
  end

  def execute_event(event)
    BetaEvents::ActionExecutor.new(beta: @user, event: event).call
  rescue BetaEvents::ActionExecutionStopped => e
    "stopped:#{e.reason}"
  end

  def create_check!(device:, status:, check_kind:, reference_time:, device_screenshot: nil, similarity_score: nil, sanctions_applied: [], details: {})
    @user.wallpaper_compliance_checks.create!(
      device: device,
      device_screenshot: device_screenshot,
      status: status,
      check_kind: check_kind,
      similarity_score: similarity_score,
      sanctions_applied: sanctions_applied,
      details: details,
      checked_at: reference_time
    )
  end
end
