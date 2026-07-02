# frozen_string_literal: true

class PosthogProductAnalytics
  class << self
    def activated_source(user, name:)
      capture(user, "activated_source", name: name.to_s)
    end

    def activated_action(user, name:)
      capture(user, "activated_action", name: name.to_s)
    end

    def configured_source(user, name:)
      capture(user, "configured_source", name: name.to_s)
    end

    def configured_action(user, name:)
      capture(user, "configured_action", name: name.to_s)
    end

    def time_added(user, seconds:, reason:, source: nil)
      properties = { seconds: seconds.to_i, reason: reason.to_s }
      properties[:source] = source.to_s if source.present?
      capture(user, "time_added", properties)
    end

    def time_added_reason(source:, metadata: {})
      metadata = (metadata || {}).stringify_keys
      source_key = source.to_s

      case source_key
      when "showcase_game"
        game = metadata["game_kind"].presence
        game ? "showcase_game:#{game}" : "showcase_game"
      when "wallpaper"
        metadata["enforcement_kind"].presence || source_key
      else
        source_key.presence || "unknown"
      end
    end

    private

    def capture(user, event, properties = {})
      return unless defined?(PostHog) && PostHog.respond_to?(:capture)

      distinct_id = user&.posthog_distinct_id
      return if distinct_id.blank?

      PostHog.capture(distinct_id: distinct_id, event: event, properties: properties)
    end
  end
end
