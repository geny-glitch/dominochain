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

  def wallpaper_scenario_trigger_summary(scenario)
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
    end
    parts.join(" · ")
  end

  def wallpaper_scenario_action_summary(possibility_id, config)
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

  def wallpaper_icon_svg(name)
    case name.to_sym
    when :pencil
      <<~SVG.html_safe
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
      SVG
    when :trash
      <<~SVG.html_safe
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
      SVG
    else
      "".html_safe
    end
  end

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

  private

  def beta_catalog
    @beta_catalog ||= BetaCatalog.new(current_user)
  end
end
