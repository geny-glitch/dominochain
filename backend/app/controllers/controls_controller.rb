# frozen_string_literal: true

class ControlsController < ApplicationController
  before_action :authenticate_user!, except: [:accept_from_link, :accept_from_link_submit]

  def accept_from_link
    return redirect_to new_user_session_path, alert: "Connectez-vous pour accepter." unless user_signed_in?

    @nickname = params[:nickname]
    @beta = User.find_by(nickname: @nickname)
    return redirect_to root_path, alert: "Beta non trouvé." unless @beta

    existing = Control.find_by(beta: @beta, boss: current_user, status: :accepted)
    return redirect_to wallpaper_upload_path(@nickname) if existing

    @control = Control.new(boss: current_user, beta: @beta)
  end

  def accept_from_link_submit
    return redirect_to new_user_session_path, alert: "Connectez-vous pour accepter." unless user_signed_in?

    @nickname = params[:nickname]
    @beta = User.find_by(nickname: @nickname)
    return redirect_to root_path, alert: "Beta non trouvé." unless @beta

    existing = Control.find_by(beta: @beta, status: :accepted)
    if existing && existing.boss != current_user
      return redirect_to dashboard_path, alert: "Ce beta est déjà contrôlé par #{existing.boss.nickname}."
    end

    Control.create!(boss: current_user, beta: @beta, status: :accepted)
    redirect_to wallpaper_upload_path(@nickname), notice: "Vous contrôlez maintenant #{@beta.nickname}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to control_accept_from_link_path(@nickname), alert: e.record.errors.full_messages.join(", ")
  end

  def release
    control = current_user.controls.accepted.find(params[:control_id])
    control.destroy!
    redirect_to dashboard_path, notice: "Beta libéré."
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Control non trouvé."
  end

  def accept_request
    request = current_user.control_requests_received.pending.find(params[:request_id])
    existing = Control.find_by(beta: request.beta)
    if existing
      return redirect_to dashboard_path, alert: "Ce beta est déjà contrôlé par #{existing.boss.nickname}." if existing.boss != current_user
      existing.destroy!
    end
    Control.create!(boss: current_user, beta: request.beta, status: :accepted)
    request.update!(status: :accepted)
    redirect_to dashboard_path, notice: "Vous contrôlez maintenant #{request.beta.nickname}."
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Demande non trouvée."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_path, alert: e.record.errors.full_messages.join(", ")
  end

  def reject_request
    request = current_user.control_requests_received.pending.find(params[:request_id])
    request.update!(status: :rejected)
    redirect_to dashboard_path, notice: "Demande refusée."
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Demande non trouvée."
  end
end
