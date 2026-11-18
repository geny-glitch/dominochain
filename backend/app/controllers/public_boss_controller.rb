# frozen_string_literal: true

class PublicBossController < ApplicationController
  include WallpaperBossOperations

  before_action :load_public_boss_context
  before_action :require_public_boss_device!, only: [ :upload_new, :screenshot_request, :upload, :set_current, :update_rotation ]

  def show
    load_boss_dashboard_data if @device
    render "wallpaper/show"
  end

  def upload_new
    if @beta.wallpaper_verification_session_locked?
      redirect_to public_boss_path(@nickname, device_id: @device_id),
                  alert: t("flash.beta.wallpaper.verification_session_locked")
      return
    end

    render "wallpaper/upload_new"
  end

  def screenshot_request
    FcmService.send_take_screenshot_notification(device: @device)
    redirect_to public_boss_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.screenshot_requested")
  end

  def upload
    kind = submit_wallpaper_images!
    notice = kind == :many ? t("flash.wallpaper.uploaded_many") : t("flash.wallpaper.uploaded")
    redirect_to public_boss_path(@nickname, device_id: @device_id), notice: notice
  rescue WallpaperVerificationSessionGuard::LockedError
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.beta.wallpaper.verification_session_locked")
  rescue WallpaperRotations::Save::TooManyPhotos
    redirect_to public_boss_upload_new_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.rotation_too_many")
  rescue ActionController::ParameterMissing
    redirect_to public_boss_upload_new_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.select_image")
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, PG::ConnectionBad
    redirect_to public_boss_upload_new_path(@nickname, device_id: @device_id),
                alert: t("flash.wallpaper.upload_failed_try_again")
  end

  def update_rotation
    playlist = save_wallpaper_rotation!
    notice = playlist.enabled? ? t("flash.wallpaper.rotation_saved") : t("flash.wallpaper.rotation_disabled")
    redirect_to public_boss_path(@nickname, device_id: @device_id), notice: notice
  rescue WallpaperRotations::Save::NeedTwoPhotos
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.rotation_need_two")
  rescue WallpaperRotations::Save::TooManyPhotos
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.rotation_too_many")
  rescue WallpaperRotations::Save::InvalidInterval
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.rotation_invalid_interval")
  rescue WallpaperVerificationSessionGuard::LockedError
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.beta.wallpaper.verification_session_locked")
  end

  def set_current
    apply_wallpaper_as_current!(params[:wallpaper_id])
    redirect_to public_boss_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.wallpaper_set_current")
  rescue WallpaperVerificationSessionGuard::LockedError
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.beta.wallpaper.verification_session_locked")
  rescue ActiveRecord::RecordNotFound
    redirect_to public_boss_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.wallpaper_not_found")
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, PG::ConnectionBad
    redirect_to public_boss_path(@nickname, device_id: @device_id),
                alert: t("flash.wallpaper.upload_failed_try_again")
  end

  private

  def load_public_boss_context
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render("showcase/not_found", status: :not_found) unless @beta&.public_boss_enabled?

    @public_boss = true
    @read_only = true
    @nickname = @beta.nickname
    @devices = @beta.devices.order(created_at: :desc)
    @device = @devices.first
    @device_id = @device&.device_id
  end

  def require_public_boss_device!
    return if @device

    redirect_to public_boss_path(@nickname), alert: t("wallpaper.no_device")
  end

  def load_boss_dashboard_data
    @applications = @device.wallpaper_applications
      .includes(wallpaper: { image_attachment: { blob: { variant_records: { image_attachment: :blob } } } })
      .recent
    @tasks = @beta.tasks.recent
    @screenshots = @device.device_screenshots
      .includes(image_attachment: { blob: { variant_records: { image_attachment: :blob } } })
      .order(captured_at: :desc)
    load_wallpaper_rotation!
    @latest_screenshot = @screenshots.first
  end
end
