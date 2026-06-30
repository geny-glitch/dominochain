# frozen_string_literal: true

module WallpaperVerificationSentry
  UNEXPECTED_INCONCLUSIVE_REASONS = %w[
    capture_before_wallpaper_change
    variants_not_ready
    compare_timeout
    compare_error
  ].freeze

  module_function

  def report_unexpected_inconclusive!(screenshot:, reason:, error: nil, extra: {})
    return unless UNEXPECTED_INCONCLUSIVE_REASONS.include?(reason.to_s)
    return unless sentry_enabled?

    Sentry.with_scope do |scope|
      scope.set_context(
        "wallpaper_verification",
        {
          screenshot_id: screenshot.id,
          device_id: screenshot.device&.device_id,
          user_id: screenshot.device&.user_id,
          user_nickname: screenshot.device&.user&.nickname,
          inconclusive_reason: reason.to_s,
          wallpaper_id: screenshot.wallpaper_id,
          captured_at: screenshot.captured_at&.iso8601,
          screen_width: screenshot.device&.screen_width,
          screen_height: screenshot.device&.screen_height
        }.merge(extra)
      )
      scope.set_tags(wallpaper_inconclusive_reason: reason.to_s)

      if error
        Sentry.capture_exception(error)
      else
        Sentry.capture_message(
          "Wallpaper verification inconclusive: #{reason}",
          level: sentry_level_for(reason)
        )
      end
    end
  end

  def sentry_enabled?
    defined?(Sentry) && Sentry.respond_to?(:initialized?) && Sentry.initialized?
  end

  def sentry_level_for(reason)
    reason.to_s == "capture_before_wallpaper_change" ? :warning : :error
  end
end
