# frozen_string_literal: true

class LocalesController < ApplicationController
  def update
    loc = normalize_locale(params[:locale])
    unless loc
      redirect_back fallback_location: locale_fallback_path, alert: t("flash.locale.invalid")
      return
    end

    session[:locale] = loc.to_s

    if user_signed_in?
      prefs = (current_user.beta_ui_prefs || {}).deep_dup
      prefs["locale"] = loc.to_s
      current_user.update!(beta_ui_prefs: prefs)
    end

    redirect_back fallback_location: locale_fallback_path, notice: t("flash.locale.updated")
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: locale_fallback_path, alert: e.record.errors.full_messages.join(", ")
  end

  private

  def locale_fallback_path
    return beta_dashboard_path if user_signed_in? && current_user.beta?
    return admin_path if user_signed_in? && current_user.admin?
    return dashboard_path if user_signed_in?

    root_path
  end
end
