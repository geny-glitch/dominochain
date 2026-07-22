# frozen_string_literal: true

class TimeZonesController < ApplicationController
  before_action :authenticate_user!

  def update
    zone_name = User.canonical_time_zone_name(params[:account_tz].presence || params[:time_zone])
    unless zone_name
      redirect_to time_zone_fallback_path, alert: t("flash.time_zone.invalid")
      return
    end

    persist_user_time_zone!(zone_name)
    redirect_to time_zone_fallback_path, notice: t(
      "flash.time_zone.updated",
      zone: helpers.account_time_zone_label(zone_name)
    )
  rescue ActiveRecord::RecordInvalid => e
    redirect_to time_zone_fallback_path, alert: e.record.errors.full_messages.join(", ")
  end

  private

  def persist_user_time_zone!(zone_name)
    now = Time.current
    User.transaction do
      # update_columns avoids intermittent dirty-tracking skips seen with update! on this attribute.
      current_user.update_columns(time_zone: zone_name, updated_at: now)
      current_user.strava_goals.update_all(time_zone: zone_name, updated_at: now)
      current_user.chess_com_goals.update_all(time_zone: zone_name, updated_at: now)
    end
    current_user.reload
  end

  def time_zone_fallback_path
    return beta_account_path if current_user.beta?
    return admin_path if current_user.admin?

    dashboard_path
  end
end
