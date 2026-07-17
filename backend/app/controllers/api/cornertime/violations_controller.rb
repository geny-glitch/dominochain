# frozen_string_literal: true

module Api
  module Cornertime
    class ViolationsController < ApplicationController
      include ApiAuthenticatable

      def create
        session = current_user.cornertime_sessions.find(params[:session_id] || params[:id])
        detected_at = parse_detected_at
        result = CornertimeViolationRecorder.new(
          session: session,
          motion_score: params[:motion_score].presence&.to_f,
          detected_at: detected_at,
          client_violation_id: params[:client_violation_id]
        ).call

        unless result.ok
          render json: {
            error: result.error,
            status: result.status,
            violation: result.violation && CornertimePayload.violation_json(result.violation)
          }.compact, status: result.http_status || :unprocessable_entity
          return
        end

        render json: {
          status: result.status,
          cooldown_remaining_seconds: result.cooldown_remaining_seconds.to_i,
          violation: CornertimePayload.violation_json(result.violation),
          session: CornertimePayload.session_json(session.reload)
        }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: I18n.t("cornertime.errors.session_not_found") }, status: :not_found
      end

      private

      def parse_detected_at
        raw = params[:detected_at].presence
        return Time.current if raw.blank?

        Time.zone.parse(raw.to_s) || Time.current
      rescue ArgumentError, TypeError
        Time.current
      end
    end
  end
end
