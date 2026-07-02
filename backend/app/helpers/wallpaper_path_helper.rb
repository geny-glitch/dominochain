# frozen_string_literal: true

module WallpaperPathHelper
  def boss_wallpaper_dashboard_path(nickname, device_id: nil)
    opts = {}
    opts[:device_id] = device_id if device_id.present?
    public_boss_view? ? public_boss_path(nickname, **opts) : wallpaper_upload_path(nickname, **opts)
  end

  def boss_wallpaper_upload_new_path(nickname, device_id: nil)
    opts = {}
    opts[:device_id] = device_id if device_id.present?
    public_boss_view? ? public_boss_upload_new_path(nickname, **opts) : wallpaper_upload_new_path(nickname, **opts)
  end

  def boss_wallpaper_screenshot_request_path(nickname, device_id: nil)
    opts = {}
    opts[:device_id] = device_id if device_id.present?
    public_boss_view? ? public_boss_screenshot_request_path(nickname, **opts) : wallpaper_screenshot_request_path(nickname, **opts)
  end

  def boss_wallpaper_upload_submit_path(nickname, device_id: nil)
    opts = {}
    opts[:device_id] = device_id if device_id.present?
    public_boss_view? ? public_boss_upload_path(nickname, **opts) : wallpaper_upload_submit_path(nickname, **opts)
  end

  def boss_wallpaper_set_current_path(nickname, wallpaper_id, device_id: nil)
    opts = {}
    opts[:device_id] = device_id if device_id.present?
    public_boss_view? ? public_boss_set_current_path(nickname, wallpaper_id, **opts) : wallpaper_set_current_path(nickname, wallpaper_id, **opts)
  end

  private

  def public_boss_view?
    @public_boss == true
  end
end
