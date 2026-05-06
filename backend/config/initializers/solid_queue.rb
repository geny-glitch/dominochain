# frozen_string_literal: true

# Solid Queue defaults to 1.day — keep finished job rows ~1 week for debugging.
if Rails.env.production?
  SolidQueue.clear_finished_jobs_after = 1.week
end
