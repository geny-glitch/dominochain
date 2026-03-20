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
      redirect_to root_path, alert: "Page introuvable."
      return
    end

    seconds = params[:seconds]&.to_i
    unless seconds.present? && seconds.positive? && seconds <= 86_400 * 365 # max 1 an
      redirect_to showcase_path(@beta.nickname), alert: "Score invalide."
      return
    end

    service = ChasterService.new(@beta)
    lock = service.current_lock
    unless lock
      redirect_to showcase_path(@beta.nickname), alert: "Indisponible pour le moment."
      return
    end

    service.add_time_to_lock(lock[:id], seconds)
    redirect_to showcase_path(@beta.nickname), notice: "Merci !"
  rescue ChasterService::Unauthorized
    redirect_to showcase_path(@beta.nickname), alert: "Indisponible pour le moment."
  rescue ChasterService::Error => e
    redirect_to showcase_path(@beta.nickname), alert: "Une erreur s'est produite."
  end
end
