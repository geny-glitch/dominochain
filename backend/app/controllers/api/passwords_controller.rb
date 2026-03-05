# frozen_string_literal: true

module Api
  class PasswordsController < ApplicationController
    include ApiAuthenticatable

    def update
      user = current_user
      unless user.valid_password?(params[:current_password])
        return render json: { error: "Mot de passe actuel incorrect" }, status: :unauthorized
      end

      if params[:password] != params[:password_confirmation]
        return render json: { error: "Les mots de passe ne correspondent pas" }, status: :unprocessable_entity
      end

      if params[:password].blank? || params[:password].length < 6
        return render json: { error: "Le mot de passe doit faire au moins 6 caractères" }, status: :unprocessable_entity
      end

      user.update!(password: params[:password], password_confirmation: params[:password_confirmation])
      head :no_content
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end
end
