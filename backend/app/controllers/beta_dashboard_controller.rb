# frozen_string_literal: true

class BetaDashboardController < ApplicationController
  layout "beta_dashboard"

  CATALOG_SOURCE_ACTIONS = {
    "sources_puryfi" => "puryfi",
    "sources_cigarettes" => "cigarettes",
    "sources_strava" => "strava",
    "sources_showcase" => "showcase",
    "sources_wallpaper" => "wallpaper"
  }.freeze
  CATALOG_ACTION_ACTIONS = {
    "actions_chaster" => "chaster",
    "actions_pishock" => "pishock"
  }.freeze

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_catalog_source_platform_enabled!
  before_action :require_catalog_action_platform_enabled!
  before_action :set_task, only: [ :task, :submit_proof ]

  def home
    @chaster_lock = fetch_chaster_lock
    @strava_primary_goal = current_user.strava_goals.enabled.recent.first
    @cigarettes_today = current_user.cigarette_entries.for_day(Date.current).sum(:count)
    @cigarettes_avg_30d = average_cigarettes_last_30_days
    @recent_time_events = current_user.chaster_time_events.recent.limit(6)
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
  end

  def sources_showcase
    @showcase_qr = generate_showcase_qr
  end

  def sources_wallpaper
    @config = current_user.ensure_wallpaper_enforcement_config!
    @device = current_user.primary_device
    @apk_url = android_app_apk_url
    @status_filter = params[:status].presence
    @wallpaper_applications = wallpaper_history_scope.limit(24)
    @compliance_checks = compliance_checks_scope.limit(24)
    @chaster_lock = fetch_chaster_lock
    @chaster_lock_can_freeze = @chaster_lock.nil? || @chaster_lock[:can_freeze] != false
  end

  def update_wallpaper_enforcement
    config = current_user.ensure_wallpaper_enforcement_config!
    config.assign_attributes(enforcement_config_params)
    config.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled]) if params.key?(:enabled)
    config.save!

    redirect_to beta_sources_wallpaper_path, notice: t("flash.beta.wallpaper.config_saved")
  rescue ActiveRecord::RecordInvalid => e
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
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
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
    enabled = params[:public_boss_enabled] == "1"
    current_user.update!(public_boss_enabled: enabled)
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
    {
      check_interval_minutes: params[:check_interval_minutes],
      dismiss_apps_before_capture: params[:dismiss_apps_before_capture],
      mismatch_delay_minutes: params[:mismatch_delay_minutes],
      permissions_lost_delay_minutes: params[:permissions_lost_delay_minutes],
      app_unreachable_delay_minutes: params[:app_unreachable_delay_minutes],
      app_unreachable_threshold_minutes: params[:app_unreachable_threshold_minutes],
      mismatch_sanction: parse_sanction_params(:mismatch_sanction),
      permissions_lost_sanction: parse_sanction_params(:permissions_lost_sanction),
      app_unreachable_sanction: parse_sanction_params(:app_unreachable_sanction)
    }.compact
  end

  def parse_sanction_params(key)
    raw = params[key]
    return nil unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    bool = ActiveModel::Type::Boolean.new
    chaster_add_time_enabled = bool.cast(raw[:chaster_add_time_enabled])
    chaster_seconds = raw[:chaster_seconds].presence&.to_i
    {
      "chaster_add_time_enabled" => chaster_add_time_enabled,
      "chaster_seconds" => chaster_add_time_enabled ? chaster_seconds : nil,
      "chaster_freeze_enabled" => bool.cast(raw[:chaster_freeze_enabled]),
      "pishock_enabled" => bool.cast(raw[:pishock_enabled]),
      "pishock_intensity" => raw[:pishock_intensity].to_i,
      "pishock_duration" => raw[:pishock_duration].to_i
    }
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
end
