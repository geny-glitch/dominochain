# frozen_string_literal: true

module Api
  class DevicesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      device_id = params.require(:device_id)
      device = Device.find_or_create_by!(device_id: device_id)
      updates = {}
      updates[:screen_width] = params[:screen_width]&.to_i if params[:screen_width].present?
      updates[:screen_height] = params[:screen_height]&.to_i if params[:screen_height].present?
      updates[:fcm_token] = params[:fcm_token] if params[:fcm_token].present?
      device.update!(updates) if updates.any?
      render json: {
        id: device.id,
        device_id: device.device_id,
        web_url: wallpaper_upload_url(device.device_id)
      }
    end

    def wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.current_wallpaper

      if wallpaper&.image&.attached?
        wallpaper.update_column(:first_downloaded_at, Time.current) if wallpaper.first_downloaded_at.nil?
        image_url = device.screen_width.present? && device.screen_height.present? ?
          polymorphic_url(wallpaper.variant_for(device)) : polymorphic_url(wallpaper.image)
        render json: {
          url: image_url,
          updated_at: wallpaper.updated_at.iso8601
        }
      else
        head :not_found
      end
    end

    def upload_wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.wallpapers.create!(image: params[:image])
      device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current)
      url = device.screen_width.present? && device.screen_height.present? ?
        polymorphic_url(wallpaper.variant_for(device)) : polymorphic_url(wallpaper.image)
      render json: {
        id: wallpaper.id,
        url: url,
        updated_at: wallpaper.updated_at.iso8601
      }
    end

    def wallpapers
      device = Device.find_by!(device_id: params[:id])
      wallpapers = device.wallpapers.order(created_at: :desc)
      render json: wallpapers.map { |w|
        next unless w.image.attached?
        {
          id: w.id,
          url: device.screen_width.present? && device.screen_height.present? ?
            polymorphic_url(w.variant_for(device)) : polymorphic_url(w.image),
          created_at: w.created_at.iso8601,
          first_downloaded_at: w.first_downloaded_at&.iso8601
        }
      }.compact
    end

    def destroy_wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.wallpapers.find(params[:wallpaper_id])
      wallpaper.destroy!
      head :no_content
    end

    def update_fcm_token
      device = Device.find_by!(device_id: params[:id])
      device.update!(fcm_token: params.require(:fcm_token))
      head :no_content
    end

    private

    def wallpaper_upload_url(device_id)
      "#{request.base_url}/w/#{device_id}"
    end
  end
end
