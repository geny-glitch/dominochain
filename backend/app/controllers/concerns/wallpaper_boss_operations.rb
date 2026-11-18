# frozen_string_literal: true

module WallpaperBossOperations
  extend ActiveSupport::Concern

  private

  def submit_wallpaper_images!
    images = uploaded_wallpaper_images
    raise ActionController::ParameterMissing, :image if images.empty?
    raise WallpaperRotations::Save::TooManyPhotos if images.size > WallpaperRotations::Schedule::MAX_PHOTOS

    if images.size > 1
      apply_wallpaper_uploads!(images)
      :many
    else
      apply_wallpaper_upload!(images.first)
      :one
    end
  end

  def uploaded_wallpaper_images
    raw = params[:images]
    list = case raw
           when nil then []
           when ActionDispatch::Http::UploadedFile then [raw]
           else Array(raw)
           end
    list = [params[:image]] if list.blank? && params[:image].present?
    list.flatten.compact.select { |file| file.respond_to?(:tempfile) }
  end

  def apply_wallpaper_uploads!(images)
    WallpaperVerificationSessionGuard.ensure_change_allowed!(@beta)

    devices = [@device] + @beta.devices.where.not(id: @device.id).to_a
    created_by_device = nil
    ActiveRecord::Base.transaction do
      created_by_device = Hash.new { |groups, device_id| groups[device_id] = [] }
      images.each do |image|
        first = @device.wallpapers.create!(image: image)
        @device.wallpaper_applications.create!(wallpaper: first, applied_at: Time.current, applied_by: "boss")
        created_by_device[@device.id] << first

        devices.drop(1).each do |other|
          copy = other.wallpapers.new
          copy.image.attach(first.image.blob)
          copy.save!
          other.wallpaper_applications.create!(wallpaper: copy, applied_at: Time.current, applied_by: "boss")
          created_by_device[other.id] << copy
        end
      end
    end

    devices.each do |device|
      enable_uploaded_rotation!(device, created_by_device[device.id])
    end
    @wallpaper = created_by_device[@device.id].last
    reset_wallpaper_enforcement_state!
  end

  def enable_uploaded_rotation!(device, wallpapers)
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
      wallpaper_ids: wallpapers.map(&:id)
    ).call
  end

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
