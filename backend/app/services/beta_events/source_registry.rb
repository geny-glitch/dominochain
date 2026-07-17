# frozen_string_literal: true

module BetaEvents
  # Declares how each catalog source's events bind to ActionRegistry possibilities.
  class SourceRegistry
    SHOWCASE_RATE_LIMIT = { window_seconds: 300, max_seconds: 172_800 }.freeze

    # Action catalogs accepted on configurable sanction forms (not possibility ids).
    WALLPAPER_CATALOGS = %w[chaster pishock leverage_photo].freeze
    STRAVA_CATALOGS = %w[leverage_photo].freeze
    CORNERTIME_CATALOGS = %w[chaster pishock leverage_photo].freeze

    EventDef = Struct.new(
      :kind,
      :mode,
      :accepted_catalogs,
      :extra_allowed,
      :bindings,
      keyword_init: true
    )
    SourceDef = Struct.new(:catalog_id, :event_source, :events, :default_event, keyword_init: true) do
      def event(kind)
        events[kind.to_sym] || default_event
      end
    end

    class << self
      def all
        @all ||= build_all.freeze
      end

      def for_event_source(event_source)
        all[event_source.to_sym]
      end

      def for_event(event)
        for_event_source(event.source)
      end

      def for_catalog(catalog_id)
        all.values.find { |s| s.catalog_id == catalog_id.to_s }
      end

      # Possibility ids for sanction forms / SanctionSet (derived from accepted_catalogs).
      def allowed_for(event_source, kind)
        source = for_event_source(event_source)
        return [] unless source

        event_def = source.event(kind)
        return [] unless event_def

        if event_def.accepted_catalogs.present?
          return ActionRegistry.user_configurable_ids(catalog_ids: event_def.accepted_catalogs)
        end

        event_def.bindings&.map { |b| b[:possibility_id].to_s } || []
      end

      # Possibility ids accepted at runtime for payload events (form ids + extras like strava chaster).
      def runtime_allowed_for(event_source, kind)
        source = for_event_source(event_source)
        return [] unless source

        event_def = source.event(kind)
        return [] unless event_def

        base = allowed_for(event_source, kind)
        extras = Array(event_def.extra_allowed).map(&:to_s)
        (base + extras).uniq
      end

      private

      def build_all
        {
          showcase_game: SourceDef.new(
            catalog_id: "showcase",
            event_source: :showcase_game,
            events: {
              score_time_applied: EventDef.new(
                kind: :score_time_applied,
                mode: :fixed,
                bindings: [
                  { possibility_id: "pishock.shock", config_resolver: :showcase_score },
                  {
                    possibility_id: "chaster.add_time",
                    config_resolver: :from_event_seconds,
                    rate_limit: SHOWCASE_RATE_LIMIT
                  }
                ]
              )
            },
            default_event: nil
          ),
          showcase_backdoor: SourceDef.new(
            catalog_id: "showcase",
            event_source: :showcase_backdoor,
            events: {
              time_committed: EventDef.new(
                kind: :time_committed,
                mode: :fixed,
                bindings: [
                  {
                    possibility_id: "chaster.add_time",
                    config_resolver: :from_event_seconds,
                    rate_limit: SHOWCASE_RATE_LIMIT
                  }
                ]
              )
            },
            default_event: nil
          ),
          strava_goal: SourceDef.new(
            catalog_id: "strava",
            event_source: :strava_goal,
            events: {
              failed_penalty: EventDef.new(
                kind: :failed_penalty,
                mode: :payload,
                accepted_catalogs: STRAVA_CATALOGS,
                # Dedicated chaster_penalty_minutes field — not shown on leverage sanction form.
                extra_allowed: %w[chaster.add_time]
              )
            },
            default_event: nil
          ),
          api_chaster: SourceDef.new(
            catalog_id: nil,
            event_source: :api_chaster,
            events: {
              add_time: EventDef.new(
                kind: :add_time,
                mode: :fixed,
                bindings: [
                  { possibility_id: "chaster.add_time", config_resolver: :from_event_seconds }
                ]
              )
            },
            default_event: nil
          ),
          puryfi: SourceDef.new(
            catalog_id: "puryfi",
            event_source: :puryfi,
            events: {
              add_time: EventDef.new(
                kind: :add_time,
                mode: :fixed,
                bindings: [
                  { possibility_id: "chaster.add_time", config_resolver: :from_event_seconds }
                ]
              )
            },
            default_event: nil
          ),
          cigarette: SourceDef.new(
            catalog_id: "cigarettes",
            event_source: :cigarette,
            events: {
              smoked_add_time: EventDef.new(
                kind: :smoked_add_time,
                mode: :fixed,
                bindings: [
                  { possibility_id: "chaster.add_time", config_resolver: :from_event_seconds }
                ]
              )
            },
            default_event: nil
          ),
          wallpaper: SourceDef.new(
            catalog_id: "wallpaper",
            event_source: :wallpaper,
            events: {
              enforcement_unfreeze: EventDef.new(
                kind: :enforcement_unfreeze,
                mode: :fixed,
                bindings: [ { possibility_id: "chaster.unfreeze" } ]
              )
            },
            default_event: EventDef.new(
              kind: :default,
              mode: :payload,
              accepted_catalogs: WALLPAPER_CATALOGS
            )
          ),
          cornertime: SourceDef.new(
            catalog_id: "cornertime",
            event_source: :cornertime,
            events: {
              movement_detected: EventDef.new(
                kind: :movement_detected,
                mode: :payload,
                accepted_catalogs: CORNERTIME_CATALOGS
              ),
              early_stop: EventDef.new(
                kind: :early_stop,
                mode: :payload,
                accepted_catalogs: CORNERTIME_CATALOGS
              )
            },
            default_event: nil
          )
        }.freeze
      end
    end
  end
end
