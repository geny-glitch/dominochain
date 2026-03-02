# frozen_string_literal: true

class WallpaperController < ApplicationController
  def show
    @device_id = params[:device_id]
    @device = Device.find_by(device_id: @device_id)
  end

  def upload
    device = Device.find_by!(device_id: params[:device_id])
    device.wallpapers.create!(image: params.require(:image))
    redirect_to wallpaper_upload_path(params[:device_id]), notice: "Wallpaper uploaded! It will appear on your device shortly."
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(params[:device_id]), alert: "Device not found. Please open the app first to register."
  rescue ActionController::ParameterMissing
    redirect_to wallpaper_upload_path(params[:device_id]), alert: "Please select an image to upload."
  end
end
