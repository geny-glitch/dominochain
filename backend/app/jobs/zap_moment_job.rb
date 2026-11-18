# frozen_string_literal: true

class ZapMomentJob < ApplicationJob
  queue_as :default

  def perform(program_id, generation, shocks, notify_intensity, notify_duration, analytics_source)
    program = ZapProgram.find_by(id: program_id)
    return unless program
    return unless program.generation_matches?(generation)
    return unless program.can_run_manual? || program.can_run_scheduled?

    beta = program.beta
    notify_beta!(beta, intensity: notify_intensity, duration: notify_duration)

    wait = 0
    Array(shocks).each do |shock|
      wait += shock["delay_seconds"].to_i.presence || shock[:delay_seconds].to_i
      intensity = shock["intensity"] || shock[:intensity]
      duration = shock["duration"] || shock[:duration]

      job = ZapShockJob
      job = job.set(wait: wait.seconds) if wait.positive?
      job.perform_later(
        program.id,
        generation,
        intensity.to_i,
        duration.to_i,
        analytics_source
      )
    end
  end

  private

  def notify_beta!(beta, intensity:, duration:)
    beta.devices.find_each do |device|
      FcmService.send_pishock_zap_notification(
        device: device,
        intensity: intensity,
        duration: duration
      )
    end
  end
end
