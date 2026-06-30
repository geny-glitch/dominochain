# frozen_string_literal: true

namespace :wallpaper do
  desc "Run scheduled wallpaper enforcement checks (prod: Solid Queue recurring task in config/recurring.yml)"
  task run_scheduled_checks: :environment do
    WallpaperScheduledCheckJob.perform_now
  end
end
