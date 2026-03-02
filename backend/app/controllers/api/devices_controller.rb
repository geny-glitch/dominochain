# frozen_string_literal: true

module Api
  class DevicesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      device_id = params.require(:device_id)
      device = Device.find_or_create_by!(device_id: device_id)
      render json: {
        id: device.id,
        device_id: device.device_id,
        web_url: wallpaper_upload_url(device.device_id)
      }
    end

    def wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.wallpapers.order(created_at: :desc).first

      if wallpaper&.image&.attached?
        render json: {
          url: polymorphic_url(wallpaper.image),
          updated_at: wallpaper.updated_at.iso8601
        }
      else
        head :not_found
      end
    end

    def upload_wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.wallpapers.create!(image: params[:image])
      render json: {
        id: wallpaper.id,
        url: polymorphic_url(wallpaper.image),
        updated_at: wallpaper.updated_at.iso8601
      }
    end

    private

    def wallpaper_upload_url(device_id)
      "#{request.base_url}/w/#{device_id}"
    end
  end
end
