# frozen_string_literal: true

module Api
  module Wallpaper
    class ConfigsController < ApplicationController
      include ApiAuthenticatable
      include WallpaperVerificationSessionGuard

      def show
        render json: WallpaperPayload.config_json(current_user, helpers: self)
      end

      def update
        if wallpaper_verification_session_locked?
          render json: { error: I18n.t("flash.beta.wallpaper.verification_session_config_locked") },
            status: :conflict
          return
        end

        config = current_user.ensure_wallpaper_enforcement_config!

        if params.key?(:enabled)
          config.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
        end
        if params.key?(:check_interval_minutes)
          config.check_interval_minutes = params[:check_interval_minutes]
        end
        if params.key?(:dismiss_apps_before_capture)
          config.dismiss_apps_before_capture =
            ActiveModel::Type::Boolean.new.cast(params[:dismiss_apps_before_capture])
        end
        if params.key?(:scenarios)
          assign_scenarios!(config)
        end

        config.save!
        PosthogProductAnalytics.configured_source(current_user, name: "wallpaper")
        render json: WallpaperPayload.config_json(current_user, helpers: self)
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      private

      def assign_scenarios!(config)
        incoming = ScenarioSet.from_params(params[:scenarios], source: :wallpaper)
        raw = params[:scenarios]
        raw_hash = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
        raw_hash = raw_hash.is_a?(Hash) ? raw_hash.deep_stringify_keys : {}
        raw_list = raw_hash["scenarios"]
        had_raw = case raw_list
        when Array then raw_list.any?
        when Hash then raw_list.any?
        else false
        end

        if incoming.any? || !had_raw
          config.assign_scenarios!(incoming)
          return
        end

        config.errors.add(:scenarios, :invalid)
        raise ActiveRecord::RecordInvalid, config
      end
    end
  end
end
