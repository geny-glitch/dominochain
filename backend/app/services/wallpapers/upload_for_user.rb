# frozen_string_literal: true

module Wallpapers
  class UploadForUser
    class Error < StandardError; end

    def initialize(user:, image: nil, images: nil, applied_by: "beta_self")
      @user = user
      @images = Array(images).compact
      @images = [image] if @images.empty? && image.present?
      @applied_by = applied_by
    end

    def call!
      raise Error, "boss_controls" if @user.controlled_by_boss?
      raise Error, "verification_session_locked" if @user.wallpaper_verification_session_locked?
      raise Error, "image_required" if @images.empty?
      raise Error, "too_many" if @images.size > WallpaperRotations::Schedule::MAX_PHOTOS

      device = @user.primary_device
      raise Error, "no_device" unless device

      wallpaper = @images.size > 1 ? upload_many!(device) : upload_one!(device, @images.first)

      WallpaperEnforcementEvaluator.new(@user).reset_mismatch_on_wallpaper_change!
      wallpaper
    end

    private

    def upload_one!(device, image)
      wallpaper = nil
      ActiveRecord::Base.transaction do
        wallpaper = device.wallpapers.create!(image: image)
        device.wallpaper_applications.create!(
          wallpaper: wallpaper,
          applied_at: Time.current,
          applied_by: @applied_by
        )
        copy_to_other_devices!(device, wallpaper)
      end

      FcmService.send_background_changed_notifications(device: device)
      wallpaper
    end

    def upload_many!(device)
      created = nil
      ActiveRecord::Base.transaction do
        created = @images.map do |image|
          wallpaper = device.wallpapers.create!(image: image)
          device.wallpaper_applications.create!(
            wallpaper: wallpaper,
            applied_at: Time.current,
            applied_by: @applied_by
          )
          copy_to_other_devices!(device, wallpaper)
          wallpaper
        end
      end

      existing = device.wallpaper_playlist
      interval = existing&.interval_seconds.to_i
      unless interval.between?(WallpaperRotations::Schedule::MIN_INTERVAL_SECONDS, WallpaperRotations::Schedule::MAX_INTERVAL_SECONDS)
        interval = 30
      end
      WallpaperRotations::Save.new(
        device: device,
        enabled: true,
        interval_seconds: interval,
        collages_enabled: existing.nil? ? true : existing.collages_enabled,
        wallpaper_ids: created.map(&:id)
      ).call
      created.last
    end

    def copy_to_other_devices!(device, wallpaper)
      @user.devices.where.not(id: device.id).find_each do |other|
        copy = other.wallpapers.new
        copy.image.attach(wallpaper.image.blob)
        copy.save!
        other.wallpaper_applications.create!(
          wallpaper: copy,
          applied_at: Time.current,
          applied_by: @applied_by
        )
      end
    end
  end
end
