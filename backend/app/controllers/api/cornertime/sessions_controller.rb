# frozen_string_literal: true

module Api
  module Cornertime
    class SessionsController < ApplicationController
      include ApiAuthenticatable

      def create
        result = CornertimeSessionStarter.new(
          user: current_user,
          client: params[:client].presence || "android",
          device: current_device
        ).call

        unless result.ok
          render json: { error: result.error }, status: result.http_status
          return
        end

        render json: {
          session: CornertimePayload.session_json(result.session),
          config: CornertimePayload.config_json(result.config)
        }, status: :created
      end

      def stop
        session = current_user.cornertime_sessions.find(params[:id])
        session.stop!
        render json: { session: CornertimePayload.session_json(session) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: I18n.t("cornertime.errors.session_not_found") }, status: :not_found
      end
    end
  end
end
