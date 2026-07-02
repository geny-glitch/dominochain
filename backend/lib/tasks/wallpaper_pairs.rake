# frozen_string_literal: true

namespace :wallpaper_pairs do
  desc "Export admin/local_match disagreements to wallpaper_pairs/ (gitignored)"
  task export_disagreements: :environment do
    overwrite = ENV["OVERWRITE"] == "1"
    exported = WallpaperPairsDatasetExporter.new.export_disagreements!(overwrite: overwrite)

    puts "Exported #{exported.size} disagreement pair(s) to #{WallpaperPairsDatasetExporter::DEFAULT_ROOT}"
    exported.each do |result|
      puts "  #{result.expected_status}/screenshot_#{result.screenshot_id}"
    end
  end
end
