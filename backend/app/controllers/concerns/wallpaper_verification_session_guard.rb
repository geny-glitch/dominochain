# frozen_string_literal: true

module WallpaperVerificationSessionGuard
  extend ActiveSupport::Concern

  class LockedError < StandardError; end

  def self.ensure_change_allowed!(user)
    raise LockedError if user&.wallpaper_verification_session_locked?
  end

  private

  def wallpaper_verification_session_locked?(user = current_user)
    user&.wallpaper_verification_sessions&.active&.exists?
  end

  def block_wallpaper_change_during_verification_session!(user: current_user, redirect_path: nil, json: false)
    return unless wallpaper_verification_session_locked?(user)

    message = t("flash.beta.wallpaper.verification_session_locked")
    if json
      render json: { error: message }, status: :conflict
      return true
    end

    redirect_to redirect_path || beta_sources_wallpaper_path, alert: message
    true
  end

  def block_wallpaper_config_change_during_verification_session!
    return unless wallpaper_verification_session_locked?

    redirect_to beta_sources_wallpaper_path, alert: t("flash.beta.wallpaper.verification_session_config_locked")
    true
  end
end
