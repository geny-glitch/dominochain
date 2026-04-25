# frozen_string_literal: true

class BackdoorController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:add_time]

  def show
    @beta = find_beta_if_backdoor_enabled
    return render "showcase/not_found", status: :not_found unless @beta

    @remaining_seconds = ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
  end

  def add_time
    @beta = find_beta_if_backdoor_enabled
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    seconds = params[:seconds].to_i
    unless seconds.positive? && seconds <= 86_400
      return backdoor_json(status: 422, error: "Montant invalide (1 s à 24 h).")
    end

    unless ShowcaseAddTimeLimiter.allow?(beta_id: @beta.id, seconds: seconds)
      cap = ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
      return backdoor_json(
        status: 429,
        error: "Limite atteinte : au plus 2 jours ajoutés sur 5 minutes. Encore #{cap} s possibles pour l’instant.",
        remaining_seconds: cap
      )
    end

    service = ChasterService.new(@beta)
    lock = service.current_lock
    unless lock
      return backdoor_json(status: 422, error: "Indisponible.")
    end

    service.add_time_to_lock(lock[:id], seconds)
    ShowcaseAddTimeLimiter.record!(beta_id: @beta.id, seconds: seconds)
    backdoor_json(
      status: 200,
      ok: true,
      remaining_seconds: ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
    )
  rescue ChasterService::Unauthorized
    backdoor_json(status: 401, error: "Indisponible.")
  rescue ChasterService::Error
    backdoor_json(status: 500, error: "Erreur.")
  end

  private

  def find_beta_if_backdoor_enabled
    nickname = params[:nickname].to_s
    return nil if nickname.blank?

    User.find_by(nickname: nickname, role: :beta, backdoor_enabled: true)
  end

  def backdoor_json(status:, **body)
    render json: body, status: status
  end
end
