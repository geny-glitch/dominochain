# frozen_string_literal: true

module BetaEvents
  # Declares scenario events and trigger field schemas per catalog source (UI + validation).
  class ScenarioRegistry
    WALLPAPER_EVENTS = {
      "mismatch" => {
        trigger_fields: {
          delay_minutes: {
            type: :integer,
            min: 0,
            max: 7 * 24 * 60,
            default: 30,
            hide_when_mode: "consecutive_failures"
          },
          mode: {
            type: :enum,
            values: %w[strict double_check consecutive_failures],
            default: "strict"
          },
          consecutive_threshold: {
            type: :integer,
            min: 2,
            max: 10,
            default: 3,
            show_when_mode: "consecutive_failures"
          }
        }
      },
      "permissions_lost" => {
        trigger_fields: {
          delay_minutes: {
            type: :integer,
            min: 0,
            max: 7 * 24 * 60,
            default: 0
          }
        }
      },
      "app_unreachable" => {
        trigger_fields: {
          threshold_minutes: {
            type: :integer,
            min: 30,
            max: 7 * 24 * 60,
            default: 120
          },
          delay_minutes: {
            type: :integer,
            min: 0,
            max: 7 * 24 * 60,
            default: 0
          }
        }
      }
    }.freeze

    CORNERTIME_EVENTS = {
      "movement_detected" => { trigger_fields: {} },
      "early_stop" => { trigger_fields: {} }
    }.freeze

    STRAVA_EVENTS = {
      "any_goal_failed" => { trigger_fields: {} },
      "goal_failed" => {
        trigger_fields: {
          goal_id: { type: :reference, ref: :strava_goal, required: true }
        }
      }
    }.freeze

    CHESS_EVENTS = {
      "any_goal_failed" => { trigger_fields: {} },
      "goal_failed" => {
        trigger_fields: {
          goal_id: { type: :reference, ref: :chess_com_goal, required: true }
        }
      }
    }.freeze

    SOURCES = {
      "wallpaper" => {
        event_source: :wallpaper,
        action_kind: :default,
        events: WALLPAPER_EVENTS
      },
      "cornertime" => {
        event_source: :cornertime,
        action_kind: :movement_detected,
        events: CORNERTIME_EVENTS
      },
      "strava" => {
        event_source: :strava_goal,
        action_kind: :failed_penalty,
        events: STRAVA_EVENTS
      },
      "chess" => {
        event_source: :chess_com_goal,
        action_kind: :failed_penalty,
        events: CHESS_EVENTS
      }
    }.freeze

    # Backward-compat alias used by older wallpaper-only callers / bootstrap.
    EVENTS = WALLPAPER_EVENTS

    class << self
      def source_ids
        SOURCES.keys
      end

      def source_def(source)
        SOURCES[source.to_s]
      end

      def events_for(source)
        source_def(source)&.dig(:events) || {}
      end

      def event_ids(source = :wallpaper)
        events_for(source).keys
      end

      def find(event, source: nil)
        event = event.to_s
        if source
          return events_for(source)[event]
        end

        SOURCES.each_value do |defn|
          found = defn[:events][event]
          return found if found
        end
        nil
      end

      def source_for_event(event)
        event = event.to_s
        SOURCES.each do |source_id, defn|
          return source_id if defn[:events].key?(event)
        end
        nil
      end

      def trigger_fields_for(event, source: nil)
        find(event, source: source)&.dig(:trigger_fields) || {}
      end

      def allowed_actions_for(source)
        defn = source_def(source)
        return [] unless defn

        SourceRegistry.allowed_for(defn[:event_source], defn[:action_kind])
      end

      def normalize_trigger(event, raw, source: nil)
        fields = trigger_fields_for(event, source: source)
        hash = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
        result = {}

        fields.each do |key, schema|
          value = hash[key.to_s]
          value = hash[key.to_sym] if value.nil?
          if value.nil? || value == ""
            result[key.to_sym] = schema[:default] if schema.key?(:default)
            next
          end

          result[key.to_sym] = normalize_field(value, schema)
        end

        result
      end

      def scenario_identity_key(event, trigger)
        event = event.to_s
        case event
        when "goal_failed"
          goal_id = (trigger[:goal_id] || trigger["goal_id"]).to_i
          "#{event}:#{goal_id}"
        else
          event
        end
      end

      private

      def normalize_field(value, schema)
        case schema[:type]
        when :reference
          value.to_i.positive? ? value.to_i : nil
        when :integer
          n = value.to_i
          n = [ n, schema[:min] ].max if schema[:min]
          n = [ n, schema[:max] ].min if schema[:max]
          n
        when :enum
          s = value.to_s
          schema[:values].include?(s) ? s : schema[:default]
        else
          value
        end
      end
    end
  end
end
