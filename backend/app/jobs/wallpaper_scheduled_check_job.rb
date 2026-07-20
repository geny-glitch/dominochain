# frozen_string_literal: true

class WallpaperScheduledCheckJob < ApplicationJob
  queue_as :default

  def perform(reference_time_iso8601 = nil)
    reference_time = reference_time_iso8601.present? ? Time.zone.parse(reference_time_iso8601) : Time.current
    WallpaperVerificationSession.expire_due!(at: reference_time)

    active_session_user_ids = WallpaperVerificationSession.active.select(:user_id)

    WallpaperEnforcementConfig
      .includes(user: :devices)
      .where(
        "wallpaper_enforcement_configs.enabled = TRUE OR wallpaper_enforcement_configs.user_id IN (?)",
        active_session_user_ids
      )
      .find_each do |config|
        next unless catalog_enabled?(config.user)
        next unless due_for_check?(config, reference_time)

        process_config!(config, reference_time)
      rescue StandardError => e
        Rails.logger.warn(
          "[WallpaperScheduledCheck] user=#{config.user_id} failed: #{e.class}: #{e.message}"
        )
      end
  end

  private

  def due_for_check?(config, reference_time)
    session = WallpaperVerificationSession.active.find_by(user_id: config.user_id)
    snapshot = WallpaperEnforcementSnapshot.new(config: config, session: session)
    snapshot.due_for_scheduled_check?(reference_time)
  end

  def catalog_enabled?(user)
    BetaCatalog.new(user).source_enabled?("wallpaper")
  end

  def process_config!(config, reference_time)
    user = config.user
    device = user.primary_device
    return unless device

    WallpaperEnforcementEvaluator.new(user).evaluate_scheduled_check!(
      device: device,
      reference_time: reference_time
    )
  end
end
