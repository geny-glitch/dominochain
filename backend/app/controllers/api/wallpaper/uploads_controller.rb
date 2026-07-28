# frozen_string_literal: true

module Api
  module Wallpaper
    class UploadsController < ApplicationController
      include ApiAuthenticatable
      include WallpaperVerificationSessionGuard

      def create
        return if block_wallpaper_change_during_verification_session!(json: true)

        wallpaper = Wallpapers::UploadForUser.new(
          user: current_user,
          image: params[:image],
          applied_by: "beta_self"
        ).call!

        device = current_user.primary_device
        render json: WallpaperPayload.upload_json(wallpaper, device: device, helpers: self),
          status: :created
      rescue Wallpapers::UploadForUser::Error => e
        status, message = upload_error(e.message)
        render json: { error: message }, status: status
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      private

      def upload_error(code)
        case code
        when "boss_controls"
          [ :forbidden, I18n.t("flash.beta.wallpaper.boss_controls_wallpaper") ]
        when "verification_session_locked"
          [ :conflict, I18n.t("flash.beta.wallpaper.verification_session_locked") ]
        when "no_device"
          [ :unprocessable_entity, I18n.t("flash.beta.wallpaper.no_device") ]
        when "image_required"
          [ :unprocessable_entity, I18n.t("flash.wallpaper.select_image") ]
        else
          [ :unprocessable_entity, code ]
        end
      end
    end
  end
end
