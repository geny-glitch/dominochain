# frozen_string_literal: true

module WallpaperPairsRegressionPaths
  COMMITTED_ROOT = Rails.root.join("spec/fixtures/files/wallpaper_pairs")
  LOCAL_ROOT = Rails.root.join("wallpaper_pairs")
  STATUSES = %w[verified mismatch].freeze

  module_function

  def roots
    [COMMITTED_ROOT, LOCAL_ROOT].select(&:directory?)
  end

  def manifest_paths(statuses: STATUSES)
    roots.flat_map do |root|
      statuses.flat_map do |status|
        Dir.glob(root.join(status, "*/manifest.json").to_s)
      end
    end.sort
  end

  def fixture_files_dir(manifest_path)
    Pathname.new(manifest_path).dirname
  end
end
