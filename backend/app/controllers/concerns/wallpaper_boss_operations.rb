# frozen_string_literal: true

module WallpaperBossOperations
  extend ActiveSupport::Concern

  private

  def apply_wallpaper_upload!(image_param)
    WallpaperVerificationSessionGuard.ensure_change_allowed!(@beta)

    other_devices = @beta.devices.where.not(id: @device.id).to_a

    first_wallpaper = nil
    ActiveRecord::Base.transaction do
      disable_wallpaper_rotation!
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

  def disable_wallpaper_rotation!
    playlist = @device.wallpaper_playlist
    playlist.update!(enabled: false) if playlist&.enabled?
  end

  def load_wallpaper_rotation!
    @wallpaper_playlist = WallpaperPlaylist
      .includes(items: { wallpaper: { image_attachment: :blob } })
      .find_by(device_id: @device.id)
    @rotation_wallpapers = @device.wallpapers
      .with_attached_image
      .order(created_at: :desc)
      .select { |wallpaper| wallpaper.image.attached? }
  end

  def save_wallpaper_rotation!
    WallpaperVerificationSessionGuard.ensure_change_allowed!(@beta)
    amount = params[:interval].to_i
    amount = 1 if amount < 1
    seconds = params[:interval_unit].to_s == "minutes" ? amount * 60 : amount
    WallpaperRotations::Save.new(
      device: @device,
      enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]),
      interval_seconds: seconds,
      collages_enabled: ActiveModel::Type::Boolean.new.cast(params[:collages]),
      wallpaper_ids: params[:wallpaper_ids]
    ).call
  end

  def apply_wallpaper_as_current!(wallpaper_id)
    WallpaperVerificationSessionGuard.ensure_change_allowed!(@beta)

    wallpaper = @device.wallpapers.find(wallpaper_id)
    other_devices = @beta.devices.where.not(id: @device.id).to_a

    ActiveRecord::Base.transaction do
      disable_wallpaper_rotation!
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
