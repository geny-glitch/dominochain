# frozen_string_literal: true

class PublicBossController < ApplicationController
  include WallpaperBossOperations

  before_action :load_public_boss_context
  before_action :require_public_boss_device!, only: [ :upload_new, :screenshot_request, :upload ]

  def show
    load_boss_dashboard_data if @device
    render "wallpaper/show"
  end

  def upload_new
    render "wallpaper/upload_new"
  end

  def screenshot_request
    FcmService.send_take_screenshot_notification(device: @device)
    redirect_to public_boss_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.screenshot_requested")
  end

  def upload
    apply_wallpaper_upload!(params.require(:image))
    redirect_to public_boss_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.uploaded")
  rescue ActionController::ParameterMissing
    redirect_to public_boss_upload_new_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.select_image")
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, PG::ConnectionBad
    redirect_to public_boss_upload_new_path(@nickname, device_id: @device_id),
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
    @latest_screenshot = @screenshots.first
  end
end
