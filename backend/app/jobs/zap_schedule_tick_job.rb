# frozen_string_literal: true

class ZapScheduleTickJob < ApplicationJob
  queue_as :default

  def perform(reference_time_iso8601 = nil)
    reference_time = if reference_time_iso8601.present?
      Time.zone.parse(reference_time_iso8601)
    else
      Time.current
    end

    ZapProgram.armed.includes(:beta, :zap_slots).find_each do |program|
      next unless program.can_run_scheduled?
      next if program.busy?(at: reference_time)

      due_slot = program.zap_slots.detect { |slot| slot.due?(at: reference_time) }
      next unless due_slot

      ZapPrograms::FireMoment.call_slot(due_slot, scheduled: true)
    rescue StandardError => e
      Rails.logger.warn(
        "[ZapScheduleTick] program=#{program.id} failed: #{e.class}: #{e.message}"
      )
    end
  end
end
