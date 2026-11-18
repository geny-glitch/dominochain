# frozen_string_literal: true

module ZapPrograms
  class FireMoment
    Result = Struct.new(:ok, :error, keyword_init: true)

    class << self
      def call_slot(slot, scheduled: true)
        new(program: slot.zap_program, slot: slot, scheduled: scheduled).call
      end

      def call_ephemeral(program, pattern_attrs)
        new(program: program, pattern_attrs: pattern_attrs, scheduled: false).call
      end
    end

    def initialize(program:, slot: nil, pattern_attrs: nil, scheduled:)
      @program = program
      @slot = slot
      @pattern_attrs = pattern_attrs
      @scheduled = scheduled
    end

    def call
      return Result.new(ok: false, error: :not_allowed) unless allowed?
      return Result.new(ok: false, error: :busy) if @program.busy?

      shocks, notify_intensity, notify_duration, busy_seconds = resolve_pattern
      return Result.new(ok: false, error: :invalid_pattern) if shocks.blank?

      claimed = @program.claim_busy!(busy_seconds)
      return Result.new(ok: false, error: :busy) unless claimed

      generation = @program.generation
      @slot.mark_fired! if @scheduled && @slot

      ZapMomentJob.perform_later(
        @program.id,
        generation,
        shocks,
        notify_intensity,
        notify_duration,
        @program.analytics_source
      )

      Result.new(ok: true, error: nil)
    end

    private

    def allowed?
      @scheduled ? @program.can_run_scheduled? : @program.can_run_manual?
    end

    def resolve_pattern
      if @slot
        [
          @slot.build_shocks,
          @slot.notify_intensity,
          @slot.notify_duration,
          @slot.estimated_busy_seconds
        ]
      else
        temp = ZapSlot.new(
          @pattern_attrs.merge(
            zap_program: @program,
            position: 0,
            schedule_kind: "daily",
            time_of_day_minutes: 0
          )
        )
        return [ [], nil, nil, 0 ] unless temp.valid?

        [
          temp.build_shocks,
          temp.notify_intensity,
          temp.notify_duration,
          temp.estimated_busy_seconds
        ]
      end
    end
  end
end
