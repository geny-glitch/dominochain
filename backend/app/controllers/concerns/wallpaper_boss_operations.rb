# frozen_string_literal: true

module WallpaperBossOperations
  extend ActiveSupport::Concern

  private

  def apply_wallpaper_upload!(image_param)
    WallpaperVerificationSessionGuard.ensure_change_allowed!(@beta)

    other_devices = @beta.devices.where.not(id: @device.id).to_a

    first_wallpaper = nil
    ActiveRecord::Base.transaction do
      first_wallpaper = @device.wallpapers.create!(image: image_param)
      @device.wallpaper_applications.create!(wallpaper: first_wallpaper, applied_at: Time.current, applied_by: "boss")

      other_devices.each do |d|
        w = d.wallpapers.new
        w.image.attach(first_wallpaper.image.blob)
        w.save!
        d.wallpaper_applications.create!(wallpaper: w, applied_at: Time.current, applied_by: "boss")
      end
    end

    @wallpaper = first_wallpaper
    reset_wallpaper_enforcement_state!
    FcmService.send_background_changed_notifications(device: @device)
  end

  def reset_wallpaper_enforcement_state!
    WallpaperEnforcementEvaluator.new(@beta).reset_mismatch_on_wallpaper_change!
  end

  def apply_wallpaper_as_current!(wallpaper_id)
    WallpaperVerificationSessionGuard.ensure_change_allowed!(@beta)

    wallpaper = @device.wallpapers.find(wallpaper_id)
    other_devices = @beta.devices.where.not(id: @device.id).to_a

    ActiveRecord::Base.transaction do
      @device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current, applied_by: "boss")

      other_devices.each do |d|
        w = d.wallpapers.new
        w.image.attach(wallpaper.image.blob)
        w.save!
        d.wallpaper_applications.create!(wallpaper: w, applied_at: Time.current, applied_by: "boss")
      end
    end

    reset_wallpaper_enforcement_state!
    FcmService.send_background_changed_notifications(device: @device)
  end
end
