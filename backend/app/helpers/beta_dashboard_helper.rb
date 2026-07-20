# frozen_string_literal: true

module BetaDashboardHelper
  def beta_source_catalog_items
    beta_catalog.source_items
  end

  def beta_action_catalog_items
    beta_catalog.action_items
  end

  def beta_visible_sidebar_source_items
    beta_catalog.visible_source_items
  end

  def beta_visible_sidebar_action_items
    beta_catalog.visible_action_items
  end

  def beta_catalog_source_enabled?(item_id)
    beta_catalog.source_enabled?(item_id)
  end

  def beta_catalog_action_enabled?(item_id)
    beta_catalog.action_enabled?(item_id)
  end

  def wallpaper_inconclusive_reason_label(reason)
    key = "beta.wallpaper_source.inconclusive_reason.#{reason}"
    I18n.exists?(key) ? t(key) : reason.to_s.humanize
  end

  def scenario_trigger_summary(scenario)
    parts = [ t("beta.scenarios.events.#{scenario.event}.label") ]
    case scenario.event
    when "mismatch"
      parts << t("beta.wallpaper_source.mismatch_sanction_modes.#{scenario.mode}")
      unless scenario.mode == WallpaperEnforcementConfig::SANCTION_MODE_CONSECUTIVE_FAILURES
        parts << t("beta.scenarios.summary.delay_minutes", count: scenario.delay_minutes)
      end
      if scenario.mode == WallpaperEnforcementConfig::SANCTION_MODE_CONSECUTIVE_FAILURES
        parts << t("beta.scenarios.summary.consecutive_threshold", count: scenario.consecutive_threshold)
      end
    when "permissions_lost"
      parts << t("beta.scenarios.summary.delay_minutes", count: scenario.delay_minutes)
    when "app_unreachable"
      parts << t("beta.scenarios.summary.threshold_minutes", count: scenario.threshold_minutes)
      parts << t("beta.scenarios.summary.delay_minutes", count: scenario.delay_minutes)
    when "movement_detected", "early_stop", "any_goal_failed"
      # No trigger fields — event label is enough.
    when "goal_failed"
      goal_id = (scenario.trigger[:goal_id] || scenario.trigger["goal_id"]).to_i
      goal = current_user.strava_goals.find_by(id: goal_id)
      parts << (goal&.name || t("beta.scenarios.summary.unknown_goal"))
    end
    parts.join(" · ")
  end
  alias wallpaper_scenario_trigger_summary scenario_trigger_summary

  def scenario_action_summary(possibility_id, config)
    cfg = (config || {}).deep_symbolize_keys
    case possibility_id.to_s
    when "chaster.add_time"
      t("beta.scenarios.summary.seconds", count: cfg[:seconds].to_i)
    when "chaster.freeze"
      t("beta.scenarios.summary.freeze")
    when "pishock.shock"
      t("beta.scenarios.summary.pishock", intensity: cfg[:intensity], duration: cfg[:duration])
    when "leverage_photo.lock"
      t("beta.scenarios.summary.leverage_lock", seconds: cfg[:seconds].to_i, mode: cfg[:target_mode])
    when "leverage_photo.delete"
      t("beta.scenarios.summary.leverage_delete", mode: cfg[:target_mode])
    else
      ""
    end
  end
  alias wallpaper_scenario_action_summary scenario_action_summary

  def scenario_icon_svg(name)
    case name.to_sym
    when :pencil
      <<~SVG.html_safe
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
      SVG
    when :trash
      <<~SVG.html_safe
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
      SVG
    when :eye
      <<~SVG.html_safe
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>
      SVG
    else
      "".html_safe
    end
  end
  alias wallpaper_icon_svg scenario_icon_svg

  def beta_nav_link(text, path, active: false)
    classes = [ "ds-beta-nav-link" ]
    classes << "ds-beta-nav-link--active" if active
    link_to text, path, class: classes.join(" ")
  end

  def beta_subnav_link(text, path, active: false)
    classes = [ "ds-beta-nav-link", "ds-beta-nav-link--sub" ]
    classes << "ds-beta-nav-link--active" if active
    link_to text, path, class: classes.join(" ")
  end

  def beta_event_source_label(source, metadata = {})
    ChasterTimeEventDescription.source_label(source, metadata)
  end

  def beta_event_summary(event)
    ChasterTimeEventDescription.for_event(event)[:summary]
  end

  def beta_signed_duration(seconds)
    sign = seconds.to_i.negative? ? "-" : "+"
    total = seconds.to_i.abs
    h = total / 3600
    m = (total % 3600) / 60
    s = total % 60
    if h.positive?
      t("beta.signed_duration.hours_mins", sign:, h:, m:)
    elsif m.positive?
      t("beta.signed_duration.mins_secs", sign:, m:, s:)
    else
      t("beta.signed_duration.secs", sign:, s:)
    end
  end

  def strava_sliding_window_options
    %w[daily weekly custom].map do |k|
      [ t("beta.strava.window_presets.#{k}"), k ]
    end
  end

  def strava_goal_target_line(goal)
    t(
      "beta.strava.recap.target",
      count: goal.required_count,
      window: goal.window_label
    )
  end

  def strava_goal_schedule_line(goal)
    t(
      "beta.strava.recap.schedule",
      time: goal.check_time_label,
      tz: goal.time_zone
    )
  end

  def strava_check_status_label(status)
    key = "beta.strava.check_status.#{status}"
    I18n.exists?(key) ? t(key) : status.to_s.humanize
  end

  def strava_activity_type_label(activity)
    activity[:sport_type].presence || activity[:type].presence || "—"
  end

  def strava_activity_duration_label(seconds)
    total = seconds.to_i
    return "—" unless total.positive?

    h = total / 3600
    m = (total % 3600) / 60
    if h.positive?
      t("beta.strava.activity.duration_hours_mins", h: h, m: m)
    else
      t("beta.strava.activity.duration_mins", m: m)
    end
  end

  def strava_activity_eligibility_label(eligibility)
    if eligibility[:eligible]
      t("beta.strava.activity.eligible")
    else
      t("beta.strava.activity.ineligible")
    end
  end

  def strava_activity_ineligibility_reasons(activity, goal, eligibility)
    return [] if eligibility[:eligible]

    eligibility[:reasons].map do |reason|
      case reason
      when :min_duration
        t("beta.strava.activity.reasons.min_duration", minutes: goal.min_duration_seconds / 60)
      when :min_calories
        t("beta.strava.activity.reasons.min_calories", calories: goal.min_calories)
      when :activity_type
        t("beta.strava.activity.reasons.activity_type", types: goal.activity_types.join(", "))
      when :device_name
        t("beta.strava.activity.reasons.device_name", devices: goal.device_names.join(", "))
      else
        reason.to_s.humanize
      end
    end
  end

  def strava_preview_result_notice(preview, goal:)
    return nil if preview.blank?

    period_start = Time.zone.parse(preview[:period_start_at].to_s).in_time_zone(goal.time_zone_object)
    period_end = Time.zone.parse(preview[:period_end_at].to_s).in_time_zone(goal.time_zone_object)
    key = preview[:status].to_s == "passed" ? "flash.strava.preview_check_passed" : "flash.strava.preview_check_failed"
    t(
      key,
      valid: preview[:valid_count],
      required: preview[:required_count],
      total: preview[:total_count],
      period_start: l(period_start, format: :short),
      period_end: l(period_end, format: :short)
    )
  end

  private

  def beta_catalog
    @beta_catalog ||= BetaCatalog.new(current_user)
  end
end
