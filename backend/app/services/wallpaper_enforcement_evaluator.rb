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

    unless device.permissions_granted_for_enforcement?(reference_time: reference_time)
      status = "permissions_missing"
      sanctions.concat(handle_permissions_lost!(config, device, reference_time))
    else
      config.reset_permissions_lost_state! if config.permissions_lost_since.present?
    end

    unless device.reachable?(threshold_minutes: config.app_unreachable_threshold_minutes, reference_time: reference_time)
      if status.blank?
        status = "app_unreachable"
        sanctions.concat(handle_app_unreachable!(config, device, reference_time))
      end
      details["last_seen_at"] = device.last_seen_at&.iso8601
    else
      config.reset_app_unreachable_state! if config.app_unreachable_since.present?
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
    details["inconclusive_reason"] = screenshot.inconclusive_reason if verification_status == "inconclusive" && screenshot.inconclusive_reason.present?

    case verification_status
    when "verified"
      sanctions.concat(handle_verified!(config, reference_time))
    when "mismatch"
      sanctions.concat(handle_mismatch!(config, device, reference_time))
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

  def handle_mismatch!(config, device, reference_time)
    case config.mismatch_sanction_mode
    when WallpaperEnforcementConfig::SANCTION_MODE_DOUBLE_CHECK
      handle_mismatch_double_check!(config, device, reference_time)
    when WallpaperEnforcementConfig::SANCTION_MODE_CONSECUTIVE_FAILURES
      handle_mismatch_consecutive_failures!(config, reference_time)
    else
      handle_mismatch_strict!(config, reference_time)
    end
  end

  def handle_mismatch_double_check!(config, device, reference_time)
    if config.mismatch_recheck_count < WallpaperEnforcementConfig::MAX_DOUBLE_CHECK_RECHECKS
      config.increment!(:mismatch_recheck_count)
      WallpaperMismatchRecheckJob.set(wait: WallpaperMismatchRecheckJob::DOUBLE_CHECK_WAIT).perform_later(device.id)
      return []
    end

    handle_mismatch_strict!(config, reference_time)
  end

  def handle_mismatch_consecutive_failures!(config, reference_time)
    sanctions = []
    config.mismatch_since ||= reference_time
    config.mismatch_consecutive_count += 1
    config.save! if config.changed?

    threshold = config.mismatch_consecutive_threshold
    return sanctions if config.mismatch_consecutive_count < threshold

    chaster_multiplier = threshold
    sanctions.concat(apply_scenario_sanctions!(
      config: config,
      sanction: config.mismatch_sanction_object,
      reference_time: reference_time,
      details: {},
      kinds: {
        chaster_add_time: :mismatch_add_time,
        chaster_freeze: :mismatch_freeze,
        pishock: :mismatch_pishock
      },
      track_freeze: true,
      chaster_seconds_multiplier: chaster_multiplier
    ))
    config.update!(
      add_time_sanction_applied_at: reference_time,
      mismatch_consecutive_count: 0
    )
    sanctions
  end

  def handle_mismatch_strict!(config, reference_time)
    sanctions = []
    config.mismatch_since ||= reference_time
    config.save! if config.changed?

    mismatch_duration = reference_time - config.mismatch_since
    return sanctions unless should_apply_mismatch_sanctions?(config, mismatch_duration)

    sanctions.concat(apply_scenario_sanctions!(
      config: config,
      sanction: config.mismatch_sanction_object,
      reference_time: reference_time,
      details: {},
      kinds: {
        chaster_add_time: :mismatch_add_time,
        chaster_freeze: :mismatch_freeze,
        pishock: :mismatch_pishock
      },
      track_freeze: true
    ))
    config.update!(add_time_sanction_applied_at: reference_time)
    sanctions
  end

  def handle_permissions_lost!(config, device, reference_time)
    config.permissions_lost_since ||= reference_time
    config.save! if config.changed?

    duration = reference_time - config.permissions_lost_since
    return [] unless should_apply_scenario_sanctions?(
      config.permissions_lost_sanction_object,
      duration,
      config.permissions_lost_delay_minutes,
      config.permissions_lost_sanction_applied_at
    )

    sanctions = apply_scenario_sanctions!(
      config: config,
      sanction: config.permissions_lost_sanction_object,
      reference_time: reference_time,
      details: { "permissions_missing" => device.permissions_missing_list },
      kinds: {
        chaster_add_time: :permissions_lost_add_time,
        chaster_freeze: :permissions_lost_freeze,
        pishock: :permissions_lost_pishock
      },
      track_freeze: true
    )
    config.update!(permissions_lost_sanction_applied_at: reference_time)
    sanctions
  end

  def handle_app_unreachable!(config, device, reference_time)
    config.app_unreachable_since ||= reference_time
    config.save! if config.changed?

    duration = reference_time - config.app_unreachable_since
    return [] unless should_apply_scenario_sanctions?(
      config.app_unreachable_sanction_object,
      duration,
      config.app_unreachable_delay_minutes,
      config.app_unreachable_sanction_applied_at
    )

    sanctions = apply_scenario_sanctions!(
      config: config,
      sanction: config.app_unreachable_sanction_object,
      reference_time: reference_time,
      details: { "last_seen_at" => device.last_seen_at&.iso8601 },
      kinds: {
        chaster_add_time: :app_unreachable_add_time,
        chaster_freeze: :app_unreachable_freeze,
        pishock: :app_unreachable_pishock
      },
      track_freeze: true
    )
    config.update!(app_unreachable_sanction_applied_at: reference_time)
    sanctions
  end

  def should_apply_mismatch_sanctions?(config, mismatch_duration)
    sanction = config.mismatch_sanction_object
    return false unless sanction.any_active?

    mismatch_duration >= config.mismatch_delay_minutes.minutes
  end

  def should_apply_scenario_sanctions?(sanction, duration, delay_minutes, applied_at)
    return false unless sanction.any_active?
    return false if applied_at.present?

    duration >= delay_minutes.minutes
  end

  def apply_scenario_sanctions!(config:, sanction:, reference_time:, details:, kinds:, track_freeze:, chaster_seconds_multiplier: 1)
    kind_map = {
      "chaster.add_time" => kinds[:chaster_add_time],
      "chaster.freeze" => kinds[:chaster_freeze],
      "pishock.shock" => kinds[:pishock],
      "leverage_photo.lock" => kinds[:leverage_photo_lock] || :leverage_photo_lock,
      "leverage_photo.delete" => kinds[:leverage_photo_delete] || :leverage_photo_delete
    }.compact

    config_overrides = {}
    if chaster_seconds_multiplier.to_i > 1
      config_overrides["chaster.add_time"] = { seconds_multiplier: chaster_seconds_multiplier }
    end

    applier = BetaEvents::SanctionApplier.new(
      beta: @user,
      source: :wallpaper,
      kind_map: kind_map,
      execute: ->(event, context) { execute_event(event, context: context) }
    )

    results = applier.apply!(
      sanction,
      metadata: details,
      config_overrides: config_overrides,
      hooks: {
        skip_freeze: lambda {
          !ChasterService.freeze_ui_enabled? ||
            (track_freeze && config.frozen_by_enforcement?) ||
            !freeze_supported_for_user?
        },
        after: lambda { |item, _result, _context|
          if item.possibility_id == "chaster.freeze" && track_freeze
            config.update!(frozen_by_enforcement: true)
          end
        }
      }
    )

    results.each { |r| r["applied_at"] = reference_time.iso8601 }
    results
  end

  def freeze_supported_for_user?
    lock = @chaster_service.current_lock
    return false unless lock

    lock[:can_freeze] != false
  end

  def unfreeze_if_needed!(config)
    return [] unless config.frozen_by_enforcement?

    event = BetaEvents::DomainEvent.new(
      beta: @user,
      source: :wallpaper,
      kind: :enforcement_unfreeze,
      payload: {
        possibility_id: "chaster.unfreeze",
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

  def execute_event(event, context: nil)
    BetaEvents::ActionExecutor.new(beta: @user, event: event, context: context).call
  rescue BetaEvents::ActionExecutionStopped => e
    "stopped:#{e.reason}"
  end

  def create_check!(device:, status:, check_kind:, reference_time:, device_screenshot: nil, similarity_score: nil, sanctions_applied: [], details: {})
    check = @user.wallpaper_compliance_checks.create!(
      device: device,
      device_screenshot: device_screenshot,
      status: status,
      check_kind: check_kind,
      similarity_score: similarity_score,
      sanctions_applied: sanctions_applied,
      details: details,
      checked_at: reference_time
    )
    WallpaperCheckResultNotifier.notify!(check)
    check
  end
end
