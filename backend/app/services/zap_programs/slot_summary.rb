# frozen_string_literal: true

module ZapPrograms
  class SlotSummary
    class << self
      def call(slot)
        when_part = schedule_text(slot)
        what_part = pattern_text(slot)
        "#{when_part} — #{what_part}"
      end

      private

      def schedule_text(slot)
        case slot.schedule_kind
        when "daily"
          I18n.t("zap_program.summary.daily", time: clock(slot.time_of_day_minutes))
        when "once"
          I18n.t(
            "zap_program.summary.once",
            datetime: I18n.l(slot.fires_at.in_time_zone(slot.zap_program.beta.time_zone_object), format: :short)
          )
        when "interval"
          if slot.window_start_minutes.present? && slot.window_end_minutes.present?
            I18n.t(
              "zap_program.summary.interval_window",
              minutes: slot.interval_minutes,
              start: clock(slot.window_start_minutes),
              finish: clock(slot.window_end_minutes)
            )
          else
            I18n.t("zap_program.summary.interval", minutes: slot.interval_minutes)
          end
        else
          ""
        end
      end

      def pattern_text(slot)
        case slot.pattern_kind
        when "single"
          I18n.t(
            "zap_program.summary.single",
            intensity: slot.intensity,
            duration: slot.duration
          )
        when "roulette"
          I18n.t(
            "zap_program.summary.roulette",
            count: slot.count,
            min: slot.intensity_min,
            max: slot.intensity_max,
            duration: slot.duration
          )
        when "burst"
          I18n.t(
            "zap_program.summary.burst",
            count: slot.count,
            intensity: slot.intensity,
            duration: slot.duration,
            gap: slot.gap_seconds
          )
        else
          ""
        end
      end

      def clock(minutes)
        format("%02d:%02d", minutes.to_i / 60, minutes.to_i % 60)
      end
    end
  end
end
