# frozen_string_literal: true

class WallpaperController < ApplicationController
  include BetaAccessControl
  include WallpaperBossOperations

  def show
    @device_id = @device.device_id
    @applications = @device.wallpaper_applications
      .includes(wallpaper: { image_attachment: { blob: { variant_records: { image_attachment: :blob } } } })
      .recent
    @tasks = @beta.tasks.recent
    @screenshots = @device.device_screenshots
      .includes(image_attachment: { blob: { variant_records: { image_attachment: :blob } } })
      .order(captured_at: :desc)
    @latest_screenshot = @screenshots.first
  end

  def upload_new
    if @beta.wallpaper_verification_session_locked?
      redirect_to wallpaper_upload_path(@nickname, device_id: @device.device_id),
                  alert: t("flash.beta.wallpaper.verification_session_locked")
      return
    end

    @device_id = @device.device_id
  end

  def screenshot_request
    FcmService.send_take_screenshot_notification(device: @device)
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.screenshot_requested")
  end

  def grant_permissions_request
    FcmService.send_grant_permissions_notification(device: @device)
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.permissions_requested")
  end

  def upload
    apply_wallpaper_upload!(params.require(:image))
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.uploaded")
  rescue WallpaperVerificationSessionGuard::LockedError
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.beta.wallpaper.verification_session_locked")
  rescue ActionController::ParameterMissing
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.select_image")
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, PG::ConnectionBad
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id),
                alert: t("flash.wallpaper.upload_failed_try_again")
  end

  def destroy
    device = @device
    wallpaper = device.wallpapers.find(params[:wallpaper_id])
    wallpaper.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.wallpaper_deleted")
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.wallpaper_not_found")
  end

  def destroy_application
    application = @device.wallpaper_applications.find(params[:id])
    application.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.history_removed")
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.entry_not_found")
  end

  def destroy_screenshot
    screenshot = @device.device_screenshots.find(params[:id])
    screenshot.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.screenshot_deleted")
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.screenshot_not_found")
  end

  def destroy_device
    device = @beta.devices.find_by(device_id: params[:device_id])
    unless device
      redirect_to wallpaper_upload_path(@nickname), alert: t("flash.wallpaper.device_not_found")
      return
    end

    remaining = @beta.devices.where.not(id: device.id).order(created_at: :desc).first
    device.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: remaining&.device_id), notice: t("flash.wallpaper.device_deleted")
  end

  def set_current
    apply_wallpaper_as_current!(params[:wallpaper_id])
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.wallpaper_set_current")
  rescue WallpaperVerificationSessionGuard::LockedError
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.beta.wallpaper.verification_session_locked")
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.wallpaper_not_found")
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, PG::ConnectionBad
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id),
                alert: t("flash.wallpaper.upload_failed_try_again")
  end
end
