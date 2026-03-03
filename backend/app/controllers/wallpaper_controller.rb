# frozen_string_literal: true

class WallpaperController < ApplicationController
  def show
    @device_id = params[:device_id]
    @device = Device.find_by(device_id: @device_id)
    @applications = @device&.wallpaper_applications&.includes(:wallpaper)&.recent || []
  end

  def upload
    device = Device.find_by!(device_id: params[:device_id])
    @wallpaper = device.wallpapers.create!(image: params.require(:image))
    device.wallpaper_applications.create!(wallpaper: @wallpaper, applied_at: Time.current)
    redirect_to wallpaper_upload_path(params[:device_id]), notice: "Wallpaper uploaded! It will appear on your device shortly."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(params[:device_id]), alert: "Device not found. Please open the app first to register."
  rescue ActionController::ParameterMissing
    redirect_to wallpaper_upload_path(params[:device_id]), alert: "Please select an image to upload."
  end

  def destroy
    device = Device.find_by!(device_id: params[:device_id])
    wallpaper = device.wallpapers.find(params[:wallpaper_id])
    wallpaper.destroy!
    redirect_to wallpaper_upload_path(params[:device_id]), notice: "Wallpaper deleted."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(params[:device_id]), alert: "Wallpaper not found."
  end

  def set_current
    device = Device.find_by!(device_id: params[:device_id])
    wallpaper = device.wallpapers.find(params[:wallpaper_id])
    device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current)
    FcmService.send_new_wallpaper_notification(device: device)
    redirect_to wallpaper_upload_path(params[:device_id]), notice: "Wallpaper défini comme fond actuel."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(params[:device_id]), alert: "Wallpaper not found."
  end
end
