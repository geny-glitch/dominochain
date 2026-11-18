# frozen_string_literal: true

class ZapShockJob < ApplicationJob
  queue_as :default

  def perform(program_id, generation, intensity, duration, analytics_source)
    program = ZapProgram.find_by(id: program_id)
    return unless program
    return unless program.generation_matches?(generation)
    return unless program.can_run_manual? || program.can_run_scheduled?

    beta = program.beta
    scaled = ShowcaseGameConfig.pishock_intensity(intensity.to_i, beta)
    result = PishockService.shock!(user: beta, intensity: scaled, duration: duration.to_i.clamp(1, 15))
    return unless result == :ok

    PosthogProductAnalytics.pishock_zap(
      beta,
      intensity: scaled,
      duration: duration.to_i,
      source: analytics_source
    )
  end
end
