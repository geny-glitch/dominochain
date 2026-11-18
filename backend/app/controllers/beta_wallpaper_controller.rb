# frozen_string_literal: true

class BetaWallpaperController < ApplicationController
  include WallpaperVerificationSessionGuard

  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_no_boss!

  def upload
    return if block_wallpaper_change_during_verification_session!

    @device = current_user.primary_device
  end

  def create
    return if block_wallpaper_change_during_verification_session!

    images = Array(params[:images]).flatten.compact
    images = [params.require(:image)] if images.empty?
    images = images.select { |file| file.respond_to?(:tempfile) }
    raise ActionController::ParameterMissing, :image if images.empty?

    Wallpapers::UploadForUser.new(
      user: current_user,
      images: images,
      applied_by: "beta_self"
    ).call!

    notice = images.size > 1 ? t("flash.wallpaper.uploaded_many") : t("flash.beta.wallpaper.uploaded")
    redirect_to beta_sources_wallpaper_path, notice: notice
  rescue ActionController::ParameterMissing
    redirect_to beta_wallpaper_upload_path, alert: t("flash.wallpaper.select_image")
  rescue Wallpapers::UploadForUser::Error => e
    alert =
      case e.message
      when "boss_controls"
        t("flash.beta.wallpaper.boss_controls_wallpaper")
      when "verification_session_locked"
        t("flash.beta.wallpaper.verification_session_locked")
      when "no_device"
        t("flash.beta.wallpaper.no_device")
      when "too_many"
        t("flash.wallpaper.rotation_too_many")
      else
        t("flash.wallpaper.select_image")
      end
    redirect_to beta_sources_wallpaper_path, alert: alert
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
