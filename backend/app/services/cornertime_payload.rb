# frozen_string_literal: true

module CornertimePayload
  module_function

  def config_json(config)
    locale = beta_locale_for(config.user)
    config.client_config_payload.merge(
      source_enabled: BetaCatalog.new(config.user).source_enabled?("cornertime"),
      locale: locale.to_s,
      voice: voice_prompts_for(locale)
    )
  end

  def session_json(session)
    {
      id: session.id,
      status: session.status,
      client: session.client,
      started_at: session.started_at&.iso8601,
      ended_at: session.ended_at&.iso8601,
      planned_duration_seconds: session.planned_duration_seconds,
      planned_duration_minutes: session.planned_duration_minutes,
      ends_at: session.ends_at&.iso8601,
      violation_count: session.violation_count
    }
  end

  def violation_json(violation)
    {
      id: violation.id,
      status: violation.status,
      detected_at: violation.detected_at&.iso8601,
      motion_score: violation.motion_score,
      actions_executed: violation.actions_executed
    }
  end

  def beta_locale_for(user)
    raw = user&.beta_ui_prefs&.dig("locale")
    return I18n.default_locale if raw.blank?

    sym = raw.to_s.downcase.tr("_", "-").split("-").first&.to_sym
    SetLocale::SUPPORTED_LOCALES.include?(sym) ? sym : I18n.default_locale
  end

  def voice_prompts_for(locale)
    {
      intro: I18n.t("cornertime.session.voice_intro", locale: locale),
      stop_moving: I18n.t("cornertime.session.voice_stop_moving", locale: locale),
      return_to_position: I18n.t("cornertime.session.voice_return_to_position", locale: locale)
    }
  end
end
