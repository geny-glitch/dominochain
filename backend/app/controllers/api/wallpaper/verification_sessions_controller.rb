# frozen_string_literal: true

module Api
  module Wallpaper
    class VerificationSessionsController < ApplicationController
      include ApiAuthenticatable

      def create
        duration_hours = params[:duration_hours].to_i
        session = WallpaperVerificationSessionStarter.new(current_user).start!(
          duration_hours: duration_hours
        )
        render json: {
          session: WallpaperPayload.verification_session_json(session)
        }, status: :created
      rescue WallpaperVerificationSessionStarter::Error => e
        message = I18n.t(
          "flash.beta.wallpaper.verification_session_start_errors.#{e.message}",
          default: e.message
        )
        status = e.message == "active_session" ? :conflict : :unprocessable_entity
        render json: { error: message }, status: status
      end
    end
  end
end
