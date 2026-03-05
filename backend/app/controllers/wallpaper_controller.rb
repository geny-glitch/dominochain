# frozen_string_literal: true

class WallpaperController < ApplicationController
  include BetaAccessControl

  def show
    @device_id = @device.device_id
    @applications = @device.wallpaper_applications.includes(:wallpaper).recent
    @tasks = @beta.tasks.recent
    @screenshots = @device.device_screenshots.order(captured_at: :desc)
  end

  def screenshot_request
    FcmService.send_take_screenshot_notification(device: @device)
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: "Demande de screenshot envoyée."
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
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: "Wallpaper uploaded! It will appear on your device shortly."
  rescue ActionController::ParameterMissing
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: "Please select an image to upload."
  end

  def destroy
    device = @device
    wallpaper = device.wallpapers.find(params[:wallpaper_id])
    wallpaper.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: "Wallpaper deleted."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: "Wallpaper not found."
  end

  def destroy_application
    application = @device.wallpaper_applications.find(params[:id])
    application.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: "Entrée supprimée de l'historique."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: "Entrée non trouvée."
  end

  def destroy_device
    device = @beta.devices.find_by(device_id: params[:device_id])
    unless device
      redirect_to wallpaper_upload_path(@nickname), alert: "Device non trouvé."
      return
    end

    remaining = @beta.devices.where.not(id: device.id).order(created_at: :desc).first
    device.destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: remaining&.device_id), notice: "Device supprimé."
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
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: "Wallpaper défini comme fond actuel."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: "Wallpaper not found."
  end
end
