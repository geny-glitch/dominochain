# frozen_string_literal: true

module WallpaperPayload
  module_function

  def config_json(user, helpers:)
    config = user.ensure_wallpaper_enforcement_config!
    session = user.active_wallpaper_verification_session
    device = user.primary_device
    catalog = BetaCatalog.new(user)
    session_locked = session.present?
    boss_controls = user.controlled_by_boss?

    display_config = if session_locked
      session.enforcement_snapshot
    else
      config
    end

    {
      source_enabled: catalog.source_enabled?("wallpaper"),
      enabled: config.enabled,
      check_interval_minutes: display_config.check_interval_minutes,
      dismiss_apps_before_capture: display_config.dismiss_apps_before_capture,
      scenarios: display_config.scenario_set.to_h,
      verification_session: verification_session_json(session),
      device: device_json(device),
      locked: boss_controls || session_locked,
      boss_controls: boss_controls,
      config_locked: session_locked,
      allowed_duration_hours: WallpaperVerificationSession::ALLOWED_DURATION_HOURS,
      leverage_action_enabled: catalog.action_platform_enabled?("leverage_photo"),
      leverage_photos: leverage_photos_summary(user, helpers: helpers)
    }
  end

  def verification_session_json(session)
    return { active: false } if session.blank?

    {
      active: true,
      id: session.id,
      ends_at: session.ends_at&.iso8601,
      started_at: session.started_at&.iso8601,
      duration_hours: session.duration_hours,
      remaining_seconds: session.remaining_seconds,
      config_locked: true
    }
  end

  def device_json(device)
    return {
      connected: false,
      permissions_ok: false,
      permissions_missing: [],
      has_current_wallpaper: false,
      fcm_token_present: false,
      reachable: false
    } if device.blank?

    threshold = device.user&.wallpaper_enforcement_config&.app_unreachable_threshold_minutes || 120
    {
      connected: true,
      name: device.display_name,
      permissions_ok: device.permissions_granted_for_enforcement?,
      permissions_missing: device.permissions_missing_list,
      has_current_wallpaper: device.current_wallpaper&.image&.attached? || false,
      fcm_token_present: device.fcm_token.present?,
      reachable: device.reachable?(threshold_minutes: threshold),
      last_seen_at: device.last_seen_at&.iso8601
    }
  end

  def upload_json(wallpaper, device:, helpers:)
    url = if device.screen_width.present? && device.screen_height.present?
      helpers.polymorphic_url(wallpaper.variant_for(device))
    else
      helpers.polymorphic_url(wallpaper.image)
    end

    {
      id: wallpaper.id,
      url: url,
      updated_at: wallpaper.updated_at.iso8601
    }
  end

  def scenario_schema_json(user)
    catalog = BetaCatalog.new(user)
    events = BetaEvents::ScenarioRegistry.events_for("wallpaper")
    allowed_ids = BetaEvents::ScenarioRegistry.allowed_actions_for("wallpaper")

    actions = allowed_ids.filter_map do |possibility_id|
      possibility = BetaEvents::ActionRegistry.find(possibility_id)
      next unless possibility
      next unless catalog.action_enabled?(possibility.catalog_id)

      {
        possibility_id: possibility.id,
        catalog_id: possibility.catalog_id,
        config_schema: serialize_schema(possibility.config_fields)
      }
    end

    {
      events: events.transform_values { |defn| { trigger_fields: serialize_schema(defn[:trigger_fields] || {}) } },
      actions: actions
    }
  end

  def leverage_photos_summary(user, helpers:)
    return [] unless BetaCatalog.new(user).action_platform_enabled?("leverage_photo")

    user.leverage_photos.not_deleted.newest_first.limit(50).map do |photo|
      {
        id: photo.id,
        status: photo.status,
        locked_until: photo.locked_until&.iso8601,
        teaser_url: attachment_url(photo.teaser_image, helpers: helpers),
        censored_url: attachment_url(photo.censored_image, helpers: helpers)
      }
    end
  end

  def attachment_url(attachment, helpers:)
    return nil unless attachment&.attached?

    helpers.rails_blob_url(attachment, only_path: false)
  rescue StandardError
    helpers.rails_blob_path(attachment, only_path: true)
  end

  def serialize_schema(fields)
    fields.each_with_object({}) do |(key, schema), memo|
      memo[key.to_s] = schema.transform_keys(&:to_s).transform_values do |v|
        v.is_a?(Symbol) ? v.to_s : v
      end
    end
  end
end
