# frozen_string_literal: true

class ShowcaseController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:add_time]

  def show
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta

    @showcase_url = showcase_url(@beta.nickname)
  end

  def add_time
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    unless @beta
      redirect_to root_path, alert: "Beta introuvable."
      return
    end

    seconds = params[:seconds]&.to_i
    unless seconds.present? && seconds.positive? && seconds <= 86_400 * 365 # max 1 an
      redirect_to showcase_path(@beta.nickname), alert: "Durée invalide (1 seconde à 1 an max)."
      return
    end

    service = ChasterService.new(@beta)
    lock = service.current_lock
    unless lock
      redirect_to showcase_path(@beta.nickname), alert: "Aucun lock actif pour ce beta."
      return
    end

    service.add_time_to_lock(lock[:id], seconds)
    redirect_to showcase_path(@beta.nickname), notice: "+#{format_duration(seconds)} ajouté au lock !"
  rescue ChasterService::Unauthorized
    redirect_to showcase_path(@beta.nickname), alert: "Chaster non connecté pour ce beta."
  rescue ChasterService::Error => e
    redirect_to showcase_path(@beta.nickname), alert: "Erreur : #{e.message}"
  end

  private

  def format_duration(seconds)
    if seconds >= 3600
      "#{seconds / 3600}h #{((seconds % 3600) / 60)}min"
    elsif seconds >= 60
      "#{seconds / 60}min"
    else
      "#{seconds}s"
    end
  end
end
