# frozen_string_literal: true

# Keeps device wallpapers in sync with a Time Vault photo while that wallpaper is still current.
# Lock → show censored (or teaser). Unlock → restore stashed original when available.
class LeveragePhotos::SyncLinkedWallpapers
  def self.on_locking!(photo, notify: true)
    new(photo).on_locking!(notify: notify)
  end

  def self.on_unlocked!(photo, notify: true)
    new(photo).on_unlocked!(notify: notify)
  end

  def initialize(photo)
    @photo = photo
  end

  def on_locking!(notify: true)
    locked = @photo.wallpaper_locked_attachment
    return [] if locked.blank?

    touched_devices = []
    each_current_linked_wallpaper do |wallpaper|
      stash_original!(wallpaper)
      wallpaper.image.attach(locked.blob)
      wallpaper.touch
      touched_devices << wallpaper.device
    end
    notify!(touched_devices) if notify
    touched_devices
  end

  def on_unlocked!(notify: true)
    touched_devices = []
    each_current_linked_wallpaper do |wallpaper|
      next unless wallpaper.leverage_original_image.attached?

      wallpaper.image.attach(wallpaper.leverage_original_image.blob)
      wallpaper.touch
      touched_devices << wallpaper.device
    end
    notify!(touched_devices) if notify
    touched_devices
  end

  private

  def each_current_linked_wallpaper
    @photo.user.devices.find_each do |device|
      wallpaper = device.current_wallpaper
      next unless wallpaper&.linked_to_leverage_photo?(@photo)

      yield wallpaper
    end
  end

  def stash_original!(wallpaper)
    return if wallpaper.leverage_original_image.attached?
    return unless @photo.original_image.attached?

    wallpaper.leverage_original_image.attach(@photo.original_image.blob)
  end

  def notify!(devices)
    unique = devices.compact.uniq
    return if unique.empty?

    FcmService.send_background_changed_notifications_to_devices(devices: unique)
  end
end
