# frozen_string_literal: true

# Sliding window: at most 2 days of Chaster time added per beta per 5 minutes
# (showcase games + page backdoor). Tracked in `showcase_add_time_events`.
class ShowcaseAddTimeLimiter
  WINDOW = 5.minutes
  MAX_SECONDS_PER_WINDOW = 2.days.to_i

  class << self
    def allow?(beta_id:, seconds:)
      remaining_capacity(beta_id) >= seconds
    end

    def record!(beta_id:, seconds:)
      ShowcaseAddTimeEvent.create!(user_id: beta_id, seconds: seconds)
    end

    def seconds_used_in_window(beta_id)
      ShowcaseAddTimeEvent
        .where(user_id: beta_id)
        .where("created_at >= ?", WINDOW.ago)
        .sum(:seconds)
    end

    def remaining_capacity(beta_id)
      [MAX_SECONDS_PER_WINDOW - seconds_used_in_window(beta_id), 0].max
    end

    # Test helper
    def reset_window!(beta_id)
      ShowcaseAddTimeEvent.where(user_id: beta_id).delete_all
    end
  end
end
