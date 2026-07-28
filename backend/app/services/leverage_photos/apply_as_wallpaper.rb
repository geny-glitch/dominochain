# frozen_string_literal: true

class LeveragePhotos::ApplyAsWallpaper
  class Error < StandardError; end

  def initialize(photo:, user:, variant: :display, censored_image_id: nil)
    @photo = photo
    @user = user
    @variant = variant.to_sym
    @censored_image_id = censored_image_id
  end

  def call!
    raise Error, "photo missing" if @photo.blank? || @photo.deleted?
    raise Error, "boss controls wallpaper" if @user.controlled_by_boss?
    raise Error, "verification session locked" if @user.wallpaper_verification_session_locked?

    devices = @user.devices.to_a
    raise Error, "no device" if devices.empty?

    display = attachment_for_variant
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

  private

  def attachment_for_variant
    if @censored_image_id.present?
      return find_censored_attachment(@censored_image_id)
    end

    case @variant
    when :censored
      @photo.preferred_censored_attachment
    when :teaser
      # Back-compat alias for the smallest censored preview.
      @photo.thumbnail_attachment
    else
      @photo.wallpaper_display_attachment
    end
  end

  def find_censored_attachment(id)
    return nil unless @photo.censored_images.attached?

    @photo.censored_images.attachments.find_by(id: id.to_i)
  end
end
