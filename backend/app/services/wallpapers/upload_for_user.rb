# frozen_string_literal: true

module Wallpapers
  class UploadForUser
    class Error < StandardError; end

    def initialize(user:, image:, applied_by: "beta_self")
      @user = user
      @image = image
      @applied_by = applied_by
    end

    def call!
      raise Error, "boss_controls" if @user.controlled_by_boss?
      raise Error, "verification_session_locked" if @user.wallpaper_verification_session_locked?
      raise Error, "image_required" if @image.blank?

      device = @user.primary_device
      raise Error, "no_device" unless device

      wallpaper = nil
      ActiveRecord::Base.transaction do
        wallpaper = device.wallpapers.create!(image: @image)
        device.wallpaper_applications.create!(
          wallpaper: wallpaper,
          applied_at: Time.current,
          applied_by: @applied_by
        )

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

      WallpaperEnforcementEvaluator.new(@user).reset_mismatch_on_wallpaper_change!
      FcmService.send_background_changed_notifications(device: device)

      wallpaper
    end
  end
end
