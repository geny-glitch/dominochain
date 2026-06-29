# frozen_string_literal: true

class WallpaperController < ApplicationController
  include BetaAccessControl

  def show
    @device_id = @device.device_id
    @applications = @device.wallpaper_applications.includes(:wallpaper).recent
    @tasks = @beta.tasks.recent
    @screenshots = @device.device_screenshots.order(captured_at: :desc)
    schedule_stale_pending_verifications(@device)
  end

  def upload_new
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
    image_param = params.require(:image)
    first_wallpaper = @device.wallpapers.create!(image: image_param)
    @device.wallpaper_applications.create!(wallpaper: first_wallpaper, applied_at: Time.current)

    @beta.devices.where.not(id: @device.id).each do |d|
      w = d.wallpapers.new
      w.image.attach(first_wallpaper.image.blob)
      w.save!
      d.wallpaper_applications.create!(wallpaper: w, applied_at: Time.current)
    end

    @wallpaper = first_wallpaper
    schedule_wallpaper_verification_screenshots([@device] + @beta.devices.where.not(id: @device.id).to_a)
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.uploaded")
  rescue ActionController::ParameterMissing
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.select_image")
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
    return redirect_to(wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.admin_only")) unless current_user.admin?

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
    device = @device
    wallpaper = device.wallpapers.find(params[:wallpaper_id])
    device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current)

    @beta.devices.where.not(id: device.id).each do |d|
      w = d.wallpapers.new
      w.image.attach(wallpaper.image.blob)
      w.save!
      d.wallpaper_applications.create!(wallpaper: w, applied_at: Time.current)
    end

    FcmService.send_background_changed_notifications(device: device)
    schedule_wallpaper_verification_screenshots([device] + @beta.devices.where.not(id: device.id).to_a)
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.wallpaper.wallpaper_set_current")
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.wallpaper.wallpaper_not_found")
  end

  private

  def schedule_wallpaper_verification_screenshots(devices)
    applied_at = Time.current.iso8601
    devices.each do |device|
      enqueue_wallpaper_job(
        WallpaperScreenshotRequestJob.set(wait: 45.seconds),
        device.id,
        applied_at
      )
    end
  end

  def schedule_stale_pending_verifications(device)
    enqueue_wallpaper_job(WallpaperStaleVerificationSweepJob, device.id)
  end

  def enqueue_wallpaper_job(job, *args)
    job.perform_later(*args)
  rescue SolidQueue::Job::EnqueueError, ActiveRecord::ConnectionNotEstablished,
         ActiveRecord::ConnectionFailed, PG::ConnectionBad => e
    job_name = job.is_a?(Class) ? job.name : job.job_class.name
    Rails.logger.warn(
      "[Wallpaper] Could not enqueue #{job_name}: #{e.class}: #{e.message}"
    )
  end
end
