# frozen_string_literal: true

module ZapProgramEditor
  extend ActiveSupport::Concern

  private

  def arm_program!(program)
    unless program.delivery_allowed?
      return redirect_back_program(program, alert: t("zap_program.flash.not_ready"))
    end

    program.arm!
    redirect_back_program(program, notice: t("zap_program.flash.armed"))
  end

  def disarm_program!(program)
    program.disarm!
    redirect_back_program(program, notice: t("zap_program.flash.disarmed"))
  end

  def create_slot!(program)
    if program.slots_full?
      return redirect_back_program(program, alert: t("zap_program.flash.slots_full"))
    end

    attrs = ZapPrograms::SlotAttributes.from_params(slot_params)
    attrs[:position] = next_slot_position(program)
    slot = program.zap_slots.build(attrs)
    if slot.save
      redirect_back_program(program, notice: t("zap_program.flash.slot_added"))
    else
      redirect_back_program(program, alert: slot.errors.full_messages.to_sentence)
    end
  end

  def update_slot!(program, slot)
    attrs = ZapPrograms::SlotAttributes.from_params(slot_params)
    if slot.update(attrs)
      redirect_back_program(program, notice: t("zap_program.flash.slot_updated"))
    else
      redirect_back_program(program, alert: slot.errors.full_messages.to_sentence)
    end
  end

  def destroy_slot!(program, slot)
    slot.destroy!
    redirect_back_program(program, notice: t("zap_program.flash.slot_removed"))
  end

  def try_slot!(program, slot)
    result = ZapPrograms::FireMoment.call_slot(slot, scheduled: false)
    redirect_back_program(program, **flash_for_fire_result(result))
  end

  def try_ephemeral!(program)
    attrs = ZapPrograms::SlotAttributes.from_params(slot_params)
    result = ZapPrograms::FireMoment.call_ephemeral(program, attrs)
    redirect_back_program(program, **flash_for_fire_result(result))
  end

  def add_starter!(program, key)
    if program.slots_full?
      return redirect_back_program(program, alert: t("zap_program.flash.slots_full"))
    end

    attrs = ZapPrograms::SlotAttributes.starter_attrs(key, beta: program.beta)
    unless attrs
      return redirect_back_program(program, alert: t("zap_program.flash.invalid_starter"))
    end

    attrs[:position] = next_slot_position(program)
    slot = program.zap_slots.build(attrs)
    if slot.save
      redirect_back_program(program, notice: t("zap_program.flash.slot_added"))
    else
      redirect_back_program(program, alert: slot.errors.full_messages.to_sentence)
    end
  end

  def slot_params
    params.require(:zap_slot).permit(
      :schedule_kind,
      :pattern_kind,
      :time_of_day,
      :time_of_day_minutes,
      :fires_at,
      :interval_minutes,
      :window_enabled,
      :window_start,
      :window_end,
      :window_start_minutes,
      :window_end_minutes,
      :intensity,
      :intensity_min,
      :intensity_max,
      :duration,
      :count,
      :gap_seconds
    ).merge(time_zone: @zap_beta.effective_time_zone)
  end

  def next_slot_position(program)
    (program.zap_slots.maximum(:position) || -1) + 1
  end

  def flash_for_fire_result(result)
    return { notice: t("zap_program.flash.try_sent") } if result.ok

    message =
      case result.error
      when :busy then t("zap_program.flash.busy")
      when :not_allowed then t("zap_program.flash.not_ready")
      else t("zap_program.flash.try_failed")
      end
    { alert: message }
  end

  def assign_editor_locals!(program)
    @zap_program = program
    @zap_beta = program.beta
    @zap_slots = program.zap_slots.to_a
    @editing_slot = @zap_slots.find { |s| s.id.to_s == params[:edit].to_s }
  end
end
