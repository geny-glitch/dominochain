# frozen_string_literal: true

module ZapPrograms
  class SlotAttributes
    class << self
      def from_params(params)
        raw = params.to_h.with_indifferent_access
        schedule_kind = raw[:schedule_kind].to_s
        pattern_kind = raw[:pattern_kind].to_s

        attrs = {
          schedule_kind: schedule_kind,
          pattern_kind: pattern_kind,
          duration: raw[:duration].to_i
        }

        case schedule_kind
        when "daily"
          attrs[:time_of_day_minutes] = parse_clock_minutes(raw[:time_of_day].presence || raw[:time_of_day_minutes])
        when "once"
          attrs[:fires_at] = parse_datetime(raw[:fires_at], time_zone: raw[:time_zone])
        when "interval"
          attrs[:interval_minutes] = raw[:interval_minutes].to_i
          if raw[:window_enabled].to_s == "1" || raw[:window_start].present? || raw[:window_end].present?
            attrs[:window_start_minutes] = parse_clock_minutes(raw[:window_start].presence || raw[:window_start_minutes])
            attrs[:window_end_minutes] = parse_clock_minutes(raw[:window_end].presence || raw[:window_end_minutes])
          end
        end

        case pattern_kind
        when "single"
          attrs[:intensity] = raw[:intensity].to_i
        when "roulette"
          attrs[:count] = raw[:count].to_i
          attrs[:intensity_min] = raw[:intensity_min].to_i
          attrs[:intensity_max] = raw[:intensity_max].to_i
        when "burst"
          attrs[:intensity] = raw[:intensity].to_i
          attrs[:count] = raw[:count].to_i
          attrs[:gap_seconds] = raw[:gap_seconds].presence&.to_i || ZapSlot::DEFAULT_GAP_SECONDS
        end

        attrs
      end

      def starter_attrs(key, beta:)
        tz = beta.time_zone_object
        tomorrow_2100 = tz.now.beginning_of_day.advance(days: 1, hours: 21)

        case key.to_s
        when "morning"
          {
            schedule_kind: "daily",
            time_of_day_minutes: 8 * 60,
            pattern_kind: "single",
            intensity: 40,
            duration: 2
          }
        when "day_roulette"
          {
            schedule_kind: "interval",
            interval_minutes: 45,
            window_start_minutes: 10 * 60,
            window_end_minutes: 20 * 60,
            pattern_kind: "roulette",
            count: 4,
            intensity_min: 15,
            intensity_max: 80,
            duration: 1
          }
        when "evening_burst"
          {
            schedule_kind: "once",
            fires_at: tomorrow_2100,
            pattern_kind: "burst",
            intensity: 50,
            count: 5,
            gap_seconds: 2,
            duration: 1
          }
        else
          nil
        end
      end

      private

      def parse_clock_minutes(value)
        return value.to_i if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

        str = value.to_s.strip
        return nil if str.blank?

        hours, minutes = str.split(":", 2).map(&:to_i)
        return nil if hours.nil? || minutes.nil?

        (hours * 60) + minutes
      end

      def parse_datetime(value, time_zone:)
        return value if value.acts_like?(:time)
        return nil if value.blank?

        zone = ActiveSupport::TimeZone[time_zone] || Time.zone
        zone.parse(value.to_s)
      end
    end
  end
end
