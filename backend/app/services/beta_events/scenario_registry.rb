# frozen_string_literal: true

module BetaEvents
  # Declares wallpaper scenario events and their trigger field schemas (UI + validation).
  class ScenarioRegistry
    EVENTS = {
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

    class << self
      def event_ids
        EVENTS.keys
      end

      def find(event)
        EVENTS[event.to_s]
      end

      def trigger_fields_for(event)
        find(event)&.dig(:trigger_fields) || {}
      end

      def normalize_trigger(event, raw)
        fields = trigger_fields_for(event)
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

      private

      def normalize_field(value, schema)
        case schema[:type]
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
