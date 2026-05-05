# frozen_string_literal: true

namespace :strava do
  desc "Check enabled Strava goals for the last completed ISO week"
  task check_weekly_goals: :environment do
    User.where.not(strava_access_token: nil).find_each do |user|
      StravaGoalCheckJob.perform_now(user.id)
    end
  end
end
