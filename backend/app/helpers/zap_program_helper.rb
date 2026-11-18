# frozen_string_literal: true

module ZapProgramHelper
  def zap_slot_summary(slot)
    ZapPrograms::SlotSummary.call(slot)
  end

  def zap_format_minutes(minutes)
    return "" if minutes.nil?

    format("%02d:%02d", minutes / 60, minutes % 60)
  end

  def zap_fires_at_local_value(slot, beta)
    return "" if slot.fires_at.blank?

    slot.fires_at.in_time_zone(beta.time_zone_object).strftime("%Y-%m-%dT%H:%M")
  end

  def zap_program_source_label(program)
    case program.source
    when "boss"
      boss_name = program.boss&.nickname.presence || t("zap_program.beta.source_boss_unknown")
      t("zap_program.beta.source_boss", nickname: boss_name)
    when "public"
      t("zap_program.beta.source_public")
    else
      program.source
    end
  end
end
