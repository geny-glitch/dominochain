# frozen_string_literal: true

class LeveragePhotos::ApplyAsWallpaper
  class Error < StandardError; end

  def initialize(photo:, user:)
    @photo = photo
    @user = user
  end

  def call!
    raise Error, "photo missing" if @photo.blank? || @photo.deleted?
    raise Error, "boss controls wallpaper" if @user.controlled_by_boss?

    devices = @user.devices.to_a
    raise Error, "no device" if devices.empty?

    display = @photo.wallpaper_display_attachment
    raise Error, "no displayable image" if display.blank?

    ActiveRecord::Base.transaction do
      devices.each do |device|
        wallpaper = device.wallpapers.create!(leverage_photo: @photo)
        wallpaper.image.attach(display.blob)
        if @photo.original_image.attached?
          wallpaper.leverage_original_image.attach(@photo.original_image.blob)
        end
        device.wallpaper_applications.create!(
          wallpaper: wallpaper,
          applied_at: Time.current,
          applied_by: "beta_self"
        )
      end
    end

    WallpaperEnforcementEvaluator.new(@user).reset_mismatch_on_wallpaper_change!
    FcmService.send_background_changed_notifications_to_devices(devices: devices)
    true
  end
end
