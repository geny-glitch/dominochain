# frozen_string_literal: true

class WallpaperScheduledCheckJob < ApplicationJob
  queue_as :default

  def perform(reference_time_iso8601 = nil)
    reference_time = reference_time_iso8601.present? ? Time.zone.parse(reference_time_iso8601) : Time.current

    WallpaperEnforcementConfig
      .due_for_check(reference_time)
      .includes(user: :devices)
      .find_each do |config|
        next unless catalog_enabled?(config.user)

        process_config!(config, reference_time)
      rescue StandardError => e
        Rails.logger.warn(
          "[WallpaperScheduledCheck] user=#{config.user_id} failed: #{e.class}: #{e.message}"
        )
      end
  end

  private

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
