# frozen_string_literal: true

class ControlsController < ApplicationController
  before_action :authenticate_user!, except: [:accept_from_link, :accept_from_link_submit]

  def accept_from_link
    return redirect_to new_user_session_path, alert: t("flash.controls.sign_in_to_accept") unless user_signed_in?

    @nickname = params[:nickname]
    @beta = User.find_by(nickname: @nickname)
    return redirect_to root_path, alert: t("flash.controls.beta_not_found") unless @beta

    existing = Control.find_by(beta: @beta, boss: current_user, status: :accepted)
    return redirect_to wallpaper_upload_path(@nickname) if existing

    @control = Control.new(boss: current_user, beta: @beta)
  end

  def accept_from_link_submit
    return redirect_to new_user_session_path, alert: t("flash.controls.sign_in_to_accept") unless user_signed_in?

    @nickname = params[:nickname]
    @beta = User.find_by(nickname: @nickname)
    return redirect_to root_path, alert: t("flash.controls.beta_not_found") unless @beta

    existing = Control.find_by(beta: @beta, status: :accepted)
    if existing && existing.boss != current_user
      return redirect_to dashboard_path, alert: t("flash.controls.already_controlled", nickname: existing.boss.nickname)
    end

    Control.create!(boss: current_user, beta: @beta, status: :accepted)
    redirect_to wallpaper_upload_path(@nickname), notice: t("flash.controls.now_controlling", nickname: @beta.nickname)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to control_accept_from_link_path(@nickname), alert: e.record.errors.full_messages.join(", ")
  end

  def release
    control = current_user.controls.accepted.find(params[:control_id])
    control.destroy!
    redirect_to dashboard_path, notice: t("flash.controls.release_ok")
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: t("flash.controls.control_not_found")
  end

  def accept_request
    request = current_user.control_requests_received.pending.find(params[:request_id])
    existing = Control.find_by(beta: request.beta)
    if existing
      return redirect_to dashboard_path, alert: t("flash.controls.already_controlled", nickname: existing.boss.nickname) if existing.boss != current_user
      existing.destroy!
    end
    Control.create!(boss: current_user, beta: request.beta, status: :accepted)
    request.update!(status: :accepted)
    redirect_to dashboard_path, notice: t("flash.controls.request_accepted", nickname: request.beta.nickname)
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: t("flash.controls.request_not_found")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_path, alert: e.record.errors.full_messages.join(", ")
  end

  def reject_request
    request = current_user.control_requests_received.pending.find(params[:request_id])
    request.update!(status: :rejected)
    redirect_to dashboard_path, notice: t("flash.controls.request_rejected")
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: t("flash.controls.request_not_found")
  end
end
