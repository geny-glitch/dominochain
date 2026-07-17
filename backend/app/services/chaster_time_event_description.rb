# frozen_string_literal: true

class ChasterTimeEventDescription
  SHOWCASE_GAMES = %w[snake dino tetris quiz].freeze

  def self.enrich_add_time(event_source:, event_kind:, payload:, summary: nil, metadata: nil)
    payload = payload.deep_symbolize_keys
    metadata = (metadata || {}).deep_symbolize_keys
    merged_metadata = extract_metadata(event_source, event_kind, payload).merge(metadata).compact
    merged_summary = summary.presence || build_summary(event_source, event_kind, merged_metadata)

    {
      summary: merged_summary,
      metadata: merged_metadata.stringify_keys
    }
  end

  def self.for_event(event)
    metadata = (event.metadata || {}).deep_symbolize_keys
    {
      source_label: source_label(event.source, metadata),
      summary: display_summary(event.source, event.summary, metadata)
    }
  end

  def self.source_label(source, metadata = {})
    key = source_label_key(source, metadata)
    I18n.t("chaster.time_events.sources.#{key}", default: source.to_s.humanize)
  end

  def self.display_summary(source, stored_summary, metadata = {})
    metadata = metadata.deep_symbolize_keys
    rebuilt = build_summary(source, nil, metadata)
    return rebuilt if rebuilt.present?

    stored_summary.presence || I18n.t("chaster.time_events.summaries.default")
  end

  def self.build_summary(event_source, event_kind, metadata)
    metadata = metadata.deep_symbolize_keys
    source = event_source.to_sym
    kind = event_kind&.to_sym

    case source
    when :showcase_game
      game_label = game_label(metadata[:game_kind])
      if metadata[:game_kind].to_s == "tetris" && metadata[:lines].present?
        I18n.t(
          "chaster.time_events.summaries.showcase_game_tetris",
          game: game_label,
          lines: metadata[:lines].to_i
        )
      else
        I18n.t("chaster.time_events.summaries.showcase_game", game: game_label)
      end
    when :showcase_backdoor
      I18n.t(
        "chaster.time_events.summaries.showcase_backdoor",
        player_name: metadata[:player_name].presence || "—",
        message: truncate_message(metadata[:message])
      )
    when :wallpaper
      wallpaper_summary(metadata[:enforcement_kind] || kind)
    when :strava_goal
      I18n.t(
        "chaster.time_events.summaries.strava_goal",
        goal_title: metadata[:goal_title].presence || "—"
      )
    when :cigarette
      I18n.t("chaster.time_events.summaries.cigarette")
    when :puryfi
      I18n.t("chaster.time_events.summaries.puryfi")
    when :api, :api_chaster
      I18n.t("chaster.time_events.summaries.api")
    when :cornertime
      I18n.t("chaster.time_events.summaries.cornertime")
    else
      nil
    end
  end

  def self.extract_metadata(event_source, event_kind, payload)
    case event_source.to_sym
    when :showcase_game
      {
        game_kind: payload[:game_kind],
        lines: payload[:lines]
      }.compact
    when :showcase_backdoor
      {
        player_name: payload[:player_name],
        message: payload[:message]
      }.compact
    when :wallpaper
      { enforcement_kind: payload[:enforcement_kind].presence || event_kind.to_s }
    when :strava_goal
      {
        goal_id: payload[:goal_id],
        goal_title: payload[:goal_title],
        due_at: payload[:due_at]
      }.compact
    else
      {}
    end
  end

  def self.source_label_key(source, metadata)
    metadata = metadata.deep_symbolize_keys
    case source.to_s
    when "showcase_game"
      game = metadata[:game_kind].to_s
      SHOWCASE_GAMES.include?(game) ? "showcase_game_#{game}" : "showcase_game"
    when "wallpaper"
      "wallpaper"
    else
      source.to_s
    end
  end

  def self.wallpaper_summary(enforcement_kind)
    key = enforcement_kind.to_s
    i18n_key = "chaster.time_events.summaries.wallpaper.#{key}"
    return I18n.t(i18n_key) if I18n.exists?(i18n_key)

    I18n.t("chaster.time_events.summaries.wallpaper.default")
  end

  def self.game_label(game_kind)
    key = game_kind.to_s
    return I18n.t("chaster.time_events.games.#{key}") if SHOWCASE_GAMES.include?(key)

    key.humanize
  end

  def self.truncate_message(message)
    message.to_s.strip.truncate(120)
  end

  private_class_method :extract_metadata, :source_label_key, :wallpaper_summary, :game_label, :truncate_message
end
