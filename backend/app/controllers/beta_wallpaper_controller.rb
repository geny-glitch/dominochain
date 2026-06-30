# frozen_string_literal: true

class BetaWallpaperController < ApplicationController
  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_no_boss!

  def upload
    @device = current_user.primary_device
  end

  def create
    device = current_user.primary_device
    unless device
      redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.no_device")
      return
    end

    image_param = params.require(:image)
    wallpaper = device.wallpapers.create!(image: image_param)
    device.wallpaper_applications.create!(
      wallpaper: wallpaper,
      applied_at: Time.current,
      applied_by: "beta_self"
    )

    current_user.devices.where.not(id: device.id).find_each do |d|
      w = d.wallpapers.new
      w.image.attach(wallpaper.image.blob)
      w.save!
      d.wallpaper_applications.create!(wallpaper: w, applied_at: Time.current, applied_by: "beta_self")
    end

    WallpaperEnforcementEvaluator.new(current_user).reset_mismatch_on_wallpaper_change!
    FcmService.send_background_changed_notifications(device: device)

    redirect_to beta_sources_wallpaper_path, notice: t("flash.beta.wallpaper.uploaded")
  rescue ActionController::ParameterMissing
    redirect_to beta_wallpaper_upload_path, alert: t("flash.wallpaper.select_image")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.beta.beta_only")
  end

  def require_no_boss!
    return unless current_user.controlled_by_boss?

    redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.boss_controls_wallpaper")
  end
end
