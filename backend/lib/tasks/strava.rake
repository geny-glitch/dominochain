# frozen_string_literal: true

namespace :strava do
  desc "Check enabled Strava goals that are due now"
  task check_due_goals: :environment do
    StravaGoalCheckJob.perform_now
  end

  desc "Deprecated alias for strava:check_due_goals"
  task check_weekly_goals: :environment do
    Rake::Task["strava:check_due_goals"].invoke
  end
end
