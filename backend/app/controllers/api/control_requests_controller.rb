# frozen_string_literal: true

module Api
  class ControlRequestsController < ApplicationController
    include ApiAuthenticatable

    def create
      boss_nickname = params.require(:boss_nickname)
      boss = User.find_by(nickname: boss_nickname, role: :boss)
      return render json: { error: "Boss non trouvé" }, status: :not_found unless boss

      beta = current_user
      return render json: { error: "Seuls les betas peuvent envoyer une demande" }, status: :unprocessable_entity unless beta.beta?

      if beta.control&.accepted?
        return render json: { error: "Vous êtes déjà contrôlé" }, status: :unprocessable_entity
      end

      request = ControlRequest.find_or_initialize_by(beta: beta, boss: boss)
      if request.persisted? && request.pending?
        return render json: { message: "Demande déjà envoyée" }, status: :ok
      end

      request.status = :pending
      request.save!
      PostHog.capture(
        distinct_id: beta.posthog_distinct_id,
        event: 'control_request_sent',
        properties: { boss_nickname: boss.nickname }
      )
      render json: { message: "Demande envoyée à #{boss.nickname}" }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end
end
