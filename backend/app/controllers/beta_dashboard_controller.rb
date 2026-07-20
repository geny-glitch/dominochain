# frozen_string_literal: true

class BetaDashboardController < ApplicationController
  include WallpaperVerificationSessionGuard

  layout "beta_dashboard"

  CATALOG_SOURCE_ACTIONS = {
    "sources_puryfi" => "puryfi",
    "sources_cigarettes" => "cigarettes",
    "sources_strava" => "strava",
    "sources_showcase" => "showcase",
    "sources_wallpaper" => "wallpaper",
    "sources_cornertime" => "cornertime"
  }.freeze
  CATALOG_ACTION_ACTIONS = {
    "actions_chaster" => "chaster",
    "actions_pishock" => "pishock",
    "actions_leverage_photo" => "leverage_photo"
  }.freeze

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_catalog_source_platform_enabled!
  before_action :require_catalog_action_platform_enabled!
  before_action :set_task, only: [ :task, :submit_proof ]
  before_action :set_strava_goal, only: [ :strava_goal ]
  before_action :require_strava_connected!, only: [ :strava_goal ]

  def home
    @chaster_lock = fetch_chaster_lock
    @strava_primary_goal = current_user.strava_goals.enabled.recent.first
    @cigarettes_today = current_user.cigarette_entries.for_day(Date.current).sum(:count)
    @cigarettes_avg_30d = average_cigarettes_last_30_days
    @recent_time_events = current_user.chaster_time_events.recent.limit(6)
    @leverage_photos = current_user.leverage_photos.not_deleted.newest_first
    @leverage_photos.each { |photo| photo.mark_unlocked! if photo.unlock_due? }
    @leverage_photo = featured_leverage_photo(@leverage_photos)
  end

  def scenarios
    @hub_entries = scenario_hub_entries
    @hub_sources = scenario_hub_enabled_sources
    @strava_goals = current_user.strava_goals.recent
    @leverage_photos = current_user.leverage_photos.not_deleted.newest_first
    @leverage_action_enabled = BetaCatalog.new(current_user).action_platform_enabled?("leverage_photo")
  end

  def create_scenario
    source = params[:source].to_s
    unless scenario_hub_enabled_sources.include?(source)
      redirect_to beta_scenarios_path, alert: t("flash.beta.scenarios.invalid_source")
      return
    end

    incoming = ScenarioSet.from_params(params[:scenarios], source: source)
    if incoming.empty?
      redirect_to beta_scenarios_path, alert: t("flash.beta.scenarios.empty_create")
      return
    end

    case source
    when "wallpaper"
      return if block_wallpaper_config_change_during_verification_session!

      config = current_user.ensure_wallpaper_enforcement_config!
      config.assign_scenarios!(merge_scenario_sets(config.scenario_set, incoming))
      config.save!
    when "cornertime"
      config = current_user.ensure_cornertime_config!
      config.assign_scenarios!(merge_scenario_sets(config.scenario_set, incoming))
      config.save!
    when "strava"
      config = current_user.ensure_strava_config!
      config.assign_scenarios!(merge_scenario_sets(config.scenario_set, incoming))
      config.save!
    end

    redirect_to beta_scenarios_path, notice: t("flash.beta.scenarios.created")
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_scenarios_path, alert: t("flash.beta.scenarios.goal_not_found")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_scenarios_path, alert: e.record.errors.full_messages.join(", ")
  end

  def sources_puryfi
    current_user.ensure_puryfi_plugin_token!
    @puryfi_ws_url = current_user.puryfi_ws_url
    @puryfi_label_ids = (0..25).to_a
    @puryfi_events_count = current_user.chaster_time_events.where(source: "puryfi").count
    @puryfi_last_event_at = current_user.chaster_time_events.where(source: "puryfi").maximum(:occurred_at)
    @puryfi_installation_collapsed = @puryfi_events_count.positive?
  end

  def sources_cigarettes
  end

  def sources_strava
    @strava_goals = current_user.strava_goals.recent.includes(:strava_goal_checks)
    @strava_config = current_user.ensure_strava_config!
    @leverage_photos = current_user.leverage_photos.not_deleted.newest_first
    @leverage_action_enabled = BetaCatalog.new(current_user).action_platform_enabled?("leverage_photo")
  end

  def strava_goal
    @checks = @goal.strava_goal_checks.recent
    @preview_result = flash[:strava_preview]&.symbolize_keys
    load_strava_goal_activities!
  end

  def update_strava_config
    config = current_user.ensure_strava_config!
    if params.key?(:scenarios)
      assign_host_scenarios!(config, source: :strava)
    end
    config.save!
    PosthogProductAnalytics.configured_source(current_user, name: "strava")
    redirect_to beta_sources_strava_path, notice: t("flash.beta.strava.consequences_saved")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_strava_path, alert: e.record.errors.full_messages.join(", ")
  end

  def sources_showcase
    @showcase_qr = generate_showcase_qr
  end

  def sources_wallpaper
    @config = current_user.ensure_wallpaper_enforcement_config!
    @verification_session = current_user.active_wallpaper_verification_session
    @verification_sessions = current_user.wallpaper_verification_sessions.recent.limit(12)
    @device = current_user.primary_device
    @apk_url = android_app_apk_url
    @status_filter = params[:status].presence
    @wallpaper_applications = wallpaper_history_scope.limit(24)
    @compliance_checks = compliance_checks_scope.limit(24)
    @chaster_lock = fetch_chaster_lock
    @leverage_photos = current_user.leverage_photos.not_deleted.newest_first
    @leverage_action_enabled = BetaCatalog.new(current_user).action_platform_enabled?("leverage_photo")
  end

  def sources_cornertime
    @config = current_user.ensure_cornertime_config!
    @sessions = current_user.cornertime_sessions.recent.includes(:cornertime_violations).limit(20)
    @leverage_photos = current_user.leverage_photos.not_deleted.newest_first
    @leverage_action_enabled = BetaCatalog.new(current_user).action_platform_enabled?("leverage_photo")
  end

  def update_cornertime_config
    config = current_user.ensure_cornertime_config!
    config.assign_attributes(cornertime_config_params)
    if params.key?(:scenarios)
      assign_host_scenarios!(config, source: :cornertime)
    end
    config.save!
    PosthogProductAnalytics.configured_source(current_user, name: "cornertime")
    redirect_to beta_sources_cornertime_path, notice: t("flash.beta.cornertime.config_saved")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_cornertime_path, alert: e.record.errors.full_messages.join(", ")
  end

  def actions_leverage_photo
    @photos = current_user.leverage_photos.not_deleted.newest_first
    @photos.each { |photo| photo.mark_unlocked! if photo.unlock_due? }
    @photo_count = @photos.size
    @recent_leverage_sanctions = recent_leverage_sanctions
  end

  def update_wallpaper_enforcement
    if wallpaper_verification_session_locked?
      message = t("flash.beta.wallpaper.verification_session_config_locked")
      if request.format.json?
        render json: { error: message }, status: :conflict
        return
      end

      redirect_to beta_sources_wallpaper_path, alert: message
      return
    end

    config = current_user.ensure_wallpaper_enforcement_config!

    if request.format.json?
      config.update!(enabled: checkbox_param_bool(:enabled))
      PosthogProductAnalytics.configured_source(current_user, name: "wallpaper")
      render json: { enabled: config.enabled }
      return
    end

    config.assign_attributes(enforcement_config_params)
    config.enabled = checkbox_param_bool(:enabled) if params.key?(:enabled)
    if params.key?(:scenarios)
      assign_host_scenarios!(config, source: :wallpaper)
    end
    config.save!
    PosthogProductAnalytics.configured_source(current_user, name: "wallpaper")

    redirect_to beta_sources_wallpaper_path, notice: t("flash.beta.wallpaper.config_saved")
  rescue ActiveRecord::RecordInvalid => e
    if request.format.json?
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      return
    end

    redirect_to beta_sources_wallpaper_path, alert: e.record.errors.full_messages.join(", ")
  end

  def test_wallpaper_enforcement_check
    unless bg_env_staging?
      redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.test_staging_only")
      return
    end

    config = current_user.ensure_wallpaper_enforcement_config!
    unless config.enabled?
      redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.test_enable_first")
      return
    end

    unless BetaCatalog.new(current_user).source_enabled?("wallpaper")
      redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.test_source_disabled")
      return
    end

    device = current_user.primary_device
    unless device
      redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.no_device")
      return
    end

    WallpaperEnforcementEvaluator.new(current_user).evaluate_scheduled_check!(
      device: device,
      reference_time: Time.current
    )
    redirect_to beta_sources_wallpaper_path, notice: t("flash.beta.wallpaper.test_triggered")
  end

  def start_wallpaper_verification_session
    duration_hours = params[:duration_hours].to_i
    session = WallpaperVerificationSessionStarter.new(current_user).start!(duration_hours: duration_hours)
    redirect_to beta_sources_wallpaper_path,
      notice: t("flash.beta.wallpaper.verification_session_started", hours: session.duration_hours)
  rescue WallpaperVerificationSessionStarter::Error => e
    redirect_to beta_sources_wallpaper_path,
      alert: t("flash.beta.wallpaper.verification_session_start_errors.#{e.message}", default: e.message)
  end

  def actions_chaster
    @chaster_lock = fetch_chaster_lock
  end

  def actions_pishock
  end

  def settings
  end

  def update_catalog_visibility
    redirect_target = catalog_visibility_redirect_target
    catalog = BetaCatalog.new(current_user)
    updated = catalog.update_item_visibility(
      kind: params[:kind],
      item_id: params[:item_id],
      enabled: params[:enabled]
    )

    unless updated
      respond_to do |format|
        format.html { redirect_to redirect_target, alert: t("flash.beta.catalog_unknown") }
        format.json { render json: { ok: false, error: t("flash.beta.catalog_unknown") }, status: :unprocessable_entity }
      end
      return
    end

    label = catalog.item_label(kind: params[:kind], item_id: params[:item_id]) || t("flash.beta.catalog_element")
    enabled = checkbox_param_bool(:enabled)
    if enabled
      item_id = params[:item_id].to_s
      case params[:kind].to_s
      when "source"
        PosthogProductAnalytics.activated_source(current_user, name: item_id)
      when "action"
        PosthogProductAnalytics.activated_action(current_user, name: item_id)
      end
    end
    message = if enabled
      t("flash.beta.catalog_activated", label:)
    else
      t("flash.beta.catalog_deactivated", label:)
    end
    respond_to do |format|
      format.html { redirect_to redirect_target, notice: message }
      format.json do
        render json: {
          ok: true,
          message: message,
          kind: params[:kind].to_s,
          item_id: params[:item_id].to_s,
          enabled: enabled
        }
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    error_message = e.record.errors.full_messages.join(", ")
    respond_to do |format|
      format.html { redirect_to redirect_target, alert: error_message }
      format.json { render json: { ok: false, error: error_message }, status: :unprocessable_entity }
    end
  end

  def account
    @control = current_user.control
    @invite_url = control_accept_from_link_url(current_user.nickname)
    @devices = current_user.devices.order(created_at: :desc)
    @tasks = current_user.tasks.recent.includes(:proof_of_completion)
  end

  def update_snake_seconds
    attrs = {
      showcase_quiz_seconds_per_point: params[:showcase_quiz_seconds_per_point].to_i,
      showcase_snake_seconds_per_fruit: params[:showcase_snake_seconds_per_fruit].to_i,
      showcase_dino_seconds_per_obstacle: params[:showcase_dino_seconds_per_obstacle].to_i,
      showcase_tetris_seconds_per_line: params[:showcase_tetris_seconds_per_line].to_i
    }
    attrs[:showcase_quiz_enabled] = params[:showcase_quiz_enabled] == "1" if params.key?(:showcase_quiz_enabled)
    attrs[:showcase_snake_enabled] = params[:showcase_snake_enabled] == "1" if params.key?(:showcase_snake_enabled)
    attrs[:showcase_dino_enabled] = params[:showcase_dino_enabled] == "1" if params.key?(:showcase_dino_enabled)
    attrs[:showcase_tetris_enabled] = params[:showcase_tetris_enabled] == "1" if params.key?(:showcase_tetris_enabled)

    current_user.update!(attrs)
    PosthogProductAnalytics.configured_source(current_user, name: "showcase")
    redirect_to beta_sources_showcase_path,
      notice: t(
        "flash.beta.game_times_saved",
        quiz: current_user.showcase_quiz_seconds_per_point,
        snake: current_user.showcase_snake_seconds_per_fruit,
        dino: current_user.showcase_dino_seconds_per_obstacle,
        tetris: current_user.showcase_tetris_seconds_per_line
      )
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_showcase_path, alert: e.record.errors.full_messages.join(", ")
  end

  def update_backdoor
    p = params.permit(:showcase_backdoor_enabled)
    enabled = p[:showcase_backdoor_enabled] == "1"
    current_user.update!(showcase_backdoor_enabled: enabled)
    PosthogProductAnalytics.configured_source(current_user, name: "showcase")
    if enabled
      redirect_to beta_sources_showcase_path,
        notice: t("flash.beta.backdoor_enabled", url: "#{request.base_url}#{showcase_backdoor_path(current_user.nickname)}")
    else
      redirect_to beta_sources_showcase_path, notice: t("flash.beta.backdoor_disabled")
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_showcase_path, alert: e.record.errors.full_messages.join(", ")
  end

  def update_public_boss
    enabled = checkbox_param_bool(:public_boss_enabled)
    current_user.update!(public_boss_enabled: enabled)
    PosthogProductAnalytics.configured_source(current_user, name: "wallpaper")
    if enabled
      redirect_to beta_sources_wallpaper_path,
        notice: t("flash.beta.public_boss_enabled", url: "#{request.base_url}#{public_boss_path(current_user.nickname)}")
    else
      redirect_to beta_sources_wallpaper_path, notice: t("flash.beta.public_boss_disabled")
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_wallpaper_path, alert: e.record.errors.full_messages.join(", ")
  end

  def update_pishock
    p = params.permit(:pishock_enabled, :pishock_username, :pishock_share_code, :pishock_api_key, :pishock_intensity_factor)
    attrs = {}
    attrs[:pishock_enabled] = p[:pishock_enabled] == "1" if p.key?(:pishock_enabled)
    attrs[:pishock_username] = p[:pishock_username].to_s.strip.presence if p.key?(:pishock_username)
    attrs[:pishock_share_code] = p[:pishock_share_code].to_s.strip.presence if p.key?(:pishock_share_code)
    attrs[:pishock_api_key] = p[:pishock_api_key] if p[:pishock_api_key].present?
    if p.key?(:pishock_intensity_factor) && p[:pishock_intensity_factor].present?
      attrs[:pishock_intensity_factor] = p[:pishock_intensity_factor].to_f.clamp(0.01, 100)
    end
    current_user.update!(attrs) if attrs.any?
    PosthogProductAnalytics.configured_action(current_user, name: "pishock") if attrs.any?
    redirect_to beta_actions_pishock_path, notice: t("flash.beta.pishock_saved")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_actions_pishock_path, alert: e.record.errors.full_messages.join(", ")
  end

  def test_pishock
    u = current_user.reload
    unless u.pishock_username.present? && u.pishock_share_code.present? && u.pishock_api_key.present?
      redirect_to beta_actions_pishock_path, alert: t("flash.beta.pishock_save_first")
      return
    end

    case PishockService.test_connection!(user: u)
    when :ok
      redirect_to beta_actions_pishock_path, notice: t("flash.beta.pishock_test_ok")
    when :auth_error
      redirect_to beta_actions_pishock_path, alert: t("flash.beta.pishock_test_auth")
    when :device_error
      redirect_to beta_actions_pishock_path, alert: t("flash.beta.pishock_test_device")
    when :skipped
      redirect_to beta_actions_pishock_path, alert: t("flash.beta.pishock_test_skipped")
    when :error
      redirect_to beta_actions_pishock_path, alert: t("flash.beta.pishock_test_error")
    end
  end

  def regenerate_puryfi_token
    current_user.regenerate_puryfi_plugin_token!
    redirect_to beta_sources_puryfi_path, notice: t("flash.beta.puryfi_regenerated")
  end

  def update_puryfi
    min_score_percent = params[:puryfi_min_score].to_f.clamp(0.0, 100.0)
    attrs = { puryfi_min_score: (min_score_percent / 100.0).round(4) }
    raw = params[:puryfi_seconds_per_label]
    if raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)
      h = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
      merged = current_user.puryfi_seconds_per_label.stringify_keys
      (0..25).each do |i|
        key = i.to_s
        next unless h.key?(key)

        merged[key] = h[key].to_i
      end
      attrs[:puryfi_seconds_per_label] = merged
    end
    current_user.update!(attrs)
    PosthogProductAnalytics.configured_source(current_user, name: "puryfi")
    redirect_to beta_sources_puryfi_path, notice: t("flash.beta.puryfi_saved")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_sources_puryfi_path, alert: e.record.errors.full_messages.join(", ")
  end

  def task
    # proof submission (layout includes sidebar)
  end

  def submit_proof
    unless @task.can_submit_proof?
      redirect_to beta_account_path, alert: t("flash.beta.proof_deadline")
      return
    end

    unless params[:text].present? || params[:media].present?
      redirect_to beta_task_path(@task), alert: t("flash.beta.proof_required")
      return
    end

    proof = @task.proof_of_completion || @task.build_proof_of_completion
    proof.text = params[:text].presence
    if params[:media].present?
      proof.media.purge if proof.media.attached?
      proof.media.attach(params[:media])
    end
    proof.status = "pending"
    proof.reviewed_at = nil
    proof.save!

    redirect_to beta_account_path, notice: t("flash.beta.proof_submitted")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_task_path(@task), alert: e.record.errors.full_messages.join(", ")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.beta.beta_only")
  end

  def require_catalog_source_platform_enabled!
    source_id = CATALOG_SOURCE_ACTIONS[action_name]
    return if source_id.blank?
    return if BetaCatalog.new(current_user).source_platform_enabled?(source_id)

    redirect_to beta_settings_path, alert: t("flash.beta.catalog_unavailable")
  end

  def require_catalog_action_platform_enabled!
    action_id = CATALOG_ACTION_ACTIONS[action_name]
    return if action_id.blank?
    return if BetaCatalog.new(current_user).action_platform_enabled?(action_id)

    redirect_to beta_settings_path, alert: t("flash.beta.catalog_unavailable")
  end

  def set_task
    @task = current_user.tasks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_account_path, alert: t("flash.beta.task_not_found")
  end

  def fetch_chaster_lock
    return nil unless current_user.chaster_access_token.present?

    ChasterService.new(current_user).current_lock
  rescue ChasterService::Unauthorized, ChasterService::Error
    nil
  end

  def generate_showcase_qr
    url = showcase_url(current_user.nickname)
    qr = RQRCode::QRCode.new(url, size: 8, level: :m)
    qr.as_svg(module_size: 4, fill: "ffffff", color: "000000")
  end

  def average_cigarettes_last_30_days
    start_date = 29.days.ago.to_date
    total = current_user.cigarette_entries.where(smoked_on: start_date..Date.current).sum(:count)
    (total / 30.0).round(1)
  end

  def catalog_visibility_redirect_target
    candidate = params[:return_to].presence || request.referer
    return beta_settings_path if candidate.blank?

    uri = URI.parse(candidate)
    path = uri.path.presence || candidate
    return beta_settings_path unless path.start_with?("/beta/") && !path.start_with?("//")

    uri.query.present? ? "#{path}?#{uri.query}" : path
  rescue URI::InvalidURIError
    beta_settings_path
  end

  def enforcement_config_params
    attrs = {
      check_interval_minutes: params[:check_interval_minutes]
    }
    if params.key?(:dismiss_apps_before_capture)
      attrs[:dismiss_apps_before_capture] = checkbox_param_bool(:dismiss_apps_before_capture)
    end
    attrs.compact
  end

  def cornertime_config_params
    {
      sensitivity: params[:sensitivity],
      violation_cooldown_seconds: params[:violation_cooldown_seconds],
      calibration_seconds: params[:calibration_seconds]
    }.compact
  end

  def assign_host_scenarios!(host, source:)
    incoming = ScenarioSet.from_params(params[:scenarios], source: source)
    raw = params[:scenarios]
    raw_hash = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    raw_hash = raw_hash.is_a?(Hash) ? raw_hash.deep_stringify_keys : {}
    raw_list = raw_hash["scenarios"]
    had_raw = case raw_list
    when Array then raw_list.any?
    when Hash then raw_list.any?
    else false
    end

    if incoming.any? || !had_raw
      host.assign_scenarios!(incoming)
      return
    end

    host.errors.add(:scenarios, :invalid)
    raise ActiveRecord::RecordInvalid, host
  end

  def wallpaper_history_scope
    device = current_user.primary_device
    return WallpaperApplication.none unless device

    scope = device.wallpaper_applications.includes(wallpaper: { image_attachment: :blob }).recent
    scope = scope.by_boss if current_user.controlled_by_boss?
    scope
  end

  def compliance_checks_scope
    scope = current_user.wallpaper_compliance_checks.recent
    scope = scope.with_status(@status_filter) if @status_filter.present?
    scope
  end

  def android_app_apk_url
    setting = AppSetting.instance
    setting.android_apk_url.presence || "#{request.base_url}/android/app.apk"
  end

  def featured_leverage_photo(photos)
    photos.find(&:unlocked?) ||
      photos.select(&:active?).min_by { |p| p.locked_until || Time.zone.at(0) } ||
      photos.first
  end

  def recent_leverage_sanctions
    wallpaper = current_user.wallpaper_compliance_checks.recent.limit(40).flat_map do |check|
      Array(check.sanctions_applied).filter_map do |sanction|
        next unless sanction.is_a?(Hash)
        action = sanction["action"].to_s
        next unless action.start_with?("leverage_photo")

        sanction.merge(
          "checked_at" => check.checked_at,
          "check_status" => check.status,
          "source" => "wallpaper"
        )
      end
    end

    strava = current_user.strava_goal_checks.order(checked_at: :desc).limit(40).flat_map do |check|
      details = check.details.is_a?(Hash) ? check.details : {}
      Array(details["sanctions_applied"]).filter_map do |sanction|
        next unless sanction.is_a?(Hash)
        action = sanction["action"].to_s
        next unless action.start_with?("leverage_photo")

        sanction.merge(
          "checked_at" => check.checked_at,
          "check_status" => check.status,
          "source" => "strava"
        )
      end
    end

    (wallpaper + strava).sort_by { |row| row["checked_at"] || Time.zone.at(0) }.reverse.first(12)
  end

  def scenario_hub_enabled_sources
    catalog = BetaCatalog.new(current_user)
    BetaEvents::ScenarioRegistry.source_ids.select do |source_id|
      catalog_id = case source_id
      when "wallpaper" then "wallpaper"
      when "cornertime" then "cornertime"
      when "strava" then "strava"
      end
      catalog_id.present? && catalog.source_platform_enabled?(catalog_id) && catalog.source_enabled?(catalog_id)
    end
  end

  def scenario_hub_entries
    entries = []
    sources = scenario_hub_enabled_sources

    if sources.include?("wallpaper")
      config = current_user.ensure_wallpaper_enforcement_config!
      config.scenario_set.scenarios.each do |scenario|
        entries << {
          source: "wallpaper",
          source_label: t("beta.scenarios.hub.sources.wallpaper"),
          scenario: scenario,
          open_path: beta_sources_wallpaper_path,
          context_label: nil
        }
      end
    end

    if sources.include?("cornertime")
      config = current_user.ensure_cornertime_config!
      config.scenario_set.scenarios.each do |scenario|
        entries << {
          source: "cornertime",
          source_label: t("beta.scenarios.hub.sources.cornertime"),
          scenario: scenario,
          open_path: beta_sources_cornertime_path,
          context_label: nil
        }
      end
    end

    if sources.include?("strava")
      config = current_user.ensure_strava_config!
      config.scenario_set.scenarios.each do |scenario|
        context_label = strava_scenario_context_label(scenario)
        entries << {
          source: "strava",
          source_label: t("beta.scenarios.hub.sources.strava"),
          scenario: scenario,
          open_path: beta_sources_strava_path,
          context_label: context_label
        }
      end
    end

    entries
  end

  def merge_scenario_sets(existing, incoming)
    scenarios = existing.scenarios.map(&:dup)
    incoming.scenarios.each do |new_scenario|
      identity = BetaEvents::ScenarioRegistry.scenario_identity_key(new_scenario.event, new_scenario.trigger)
      match = scenarios.find do |s|
        BetaEvents::ScenarioRegistry.scenario_identity_key(s.event, s.trigger) == identity
      end
      if match
        existing_pids = match.actions.map { |a| (a[:possibility_id] || a["possibility_id"]).to_s }
        new_scenario.actions.each do |action|
          pid = (action[:possibility_id] || action["possibility_id"]).to_s
          next if existing_pids.include?(pid)

          match.actions << action
          existing_pids << pid
        end
        match.trigger = new_scenario.trigger if new_scenario.trigger.present?
      else
        scenarios << new_scenario
      end
    end
    ScenarioSet.new(scenarios: scenarios)
  end

  def strava_scenario_context_label(scenario)
    case scenario.event
    when "goal_failed"
      goal_id = (scenario.trigger[:goal_id] || scenario.trigger["goal_id"]).to_i
      goal = current_user.strava_goals.find_by(id: goal_id)
      goal&.name
    end
  end

  STRAVA_GOAL_ACTIVITIES_PER_PAGE = 15

  def set_strava_goal
    @goal = current_user.strava_goals.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_sources_strava_path, alert: t("flash.strava.goal_not_found")
  end

  def require_strava_connected!
    return if current_user.reload.strava_access_token.present?

    redirect_to beta_sources_strava_path, alert: t("flash.strava.connect_first")
  end

  def load_strava_goal_activities!
    @activities_error = nil
    @activities_error_message = nil

    evaluator = StravaGoalEvaluator.new(current_user)
    window = evaluator.activities_for_goal_window(@goal)
    @activity_window = window.slice(:due_at, :period_start_at, :period_end_at)
    @activities_fetched_at = Time.current

    annotated = window[:activities].map do |activity|
      eligibility = evaluator.activity_eligibility(activity, @goal)
      { activity: activity, eligibility: eligibility }
    end
    annotated.sort_by! { |row| row[:activity][:started_at] || Time.zone.at(0) }.reverse!

    @show_all_activities = params[:show_all] == "1"
    listed = @show_all_activities ? annotated : annotated.select { |row| row[:eligibility][:eligible] }

    @activities_total_count = listed.size
    @activities_page = [ params[:page].to_i, 1 ].max
    offset = (@activities_page - 1) * STRAVA_GOAL_ACTIVITIES_PER_PAGE
    @activities_rows = listed.slice(offset, STRAVA_GOAL_ACTIVITIES_PER_PAGE) || []
    @activities_total_pages = [ (@activities_total_count.to_f / STRAVA_GOAL_ACTIVITIES_PER_PAGE).ceil, 1 ].max
    @eligible_activity_count = annotated.count { |row| row[:eligibility][:eligible] }
    @all_activity_count = annotated.size
  rescue StravaService::IntegrationUnavailable
    @activities_error = :integration_unavailable
    @activities_error_message = if Rails.env.development?
      t("beta.strava.goal_page.activities_integration_inactive_dev")
    else
      t("beta.strava.goal_page.activities_integration_unavailable")
    end
    assign_empty_strava_goal_activities!
  rescue StravaService::Unauthorized
    @activities_error = :unauthorized
    @activities_error_message = t("beta.strava.goal_page.activities_unauthorized")
    assign_empty_strava_goal_activities!
  rescue StravaService::Error => e
    @activities_error = :error
    @activities_error_message = t("beta.strava.goal_page.activities_load_failed", message: e.message)
    assign_empty_strava_goal_activities!
  end

  def assign_empty_strava_goal_activities!
    due_at = @goal.next_due_at
    @activity_window = {
      due_at: due_at,
      period_start_at: @goal.period_start_for(due_at),
      period_end_at: [ Time.current, due_at ].min
    }
    @activities_fetched_at = Time.current
    @show_all_activities = params[:show_all] == "1"
    @activities_rows = []
    @activities_total_count = 0
    @activities_page = 1
    @activities_total_pages = 1
    @eligible_activity_count = 0
    @all_activity_count = 0
  end
end
