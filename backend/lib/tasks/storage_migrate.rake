# frozen_string_literal: true

namespace :storage do
  desc "Copy Active Storage blobs and the Android APK from local disk to Tigris (use DRY_RUN=1 to preview)"
  task migrate_to_tigris: :environment do
    dry_run = ENV["DRY_RUN"].present?
    tigris = ActiveStorage::Blob.services.fetch(:tigris)
    local = ActiveStorage::Blob.services.fetch(:local)
    migrated_blobs = 0
    skipped_blobs = 0

    unless TigrisObjectStorage.configured?
      abort "Tigris is not configured. Set AWS_* and BUCKET_NAME secrets first."
    end

    puts dry_run ? "DRY RUN — no uploads" : "Migrating blobs to Tigris..."

    ActiveStorage::Blob.where(service_name: "local").find_each do |blob|
      target_key = TigrisObjectStorage.prefixed_key(blob.key)

      if tigris.exist?(target_key)
        puts "  skip blob #{blob.id} (#{blob.key}) — already on Tigris"
        skipped_blobs += 1
        next unless blob.key != target_key || blob.service_name != "tigris"

        unless dry_run
          blob.update!(service_name: "tigris", key: target_key)
          migrated_blobs += 1
        end
        next
      end

      unless local.exist?(blob.key)
        puts "  warn blob #{blob.id} (#{blob.key}) — missing on local disk"
        skipped_blobs += 1
        next
      end

      puts "  #{dry_run ? 'would migrate' : 'migrating'} blob #{blob.id} (#{blob.key} -> #{target_key})"
      next if dry_run

      blob.open do |file|
        tigris.upload(
          target_key,
          file,
          checksum: blob.checksum,
          content_type: blob.content_type,
          identify: false
        )
      end

      blob.update!(service_name: "tigris", key: target_key)
      migrated_blobs += 1
    end

    apk_path = Rails.root.join("storage", "android", "app.apk")
    if File.exist?(apk_path)
      puts "  #{dry_run ? 'would migrate' : 'migrating'} android/app.apk"
      AndroidApkStorage.upload(apk_path) unless dry_run
    else
      puts "  no local android/app.apk to migrate"
    end

    puts "Done. migrated=#{migrated_blobs} skipped=#{skipped_blobs} dry_run=#{dry_run}"
  end
end
