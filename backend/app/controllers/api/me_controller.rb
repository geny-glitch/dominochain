# frozen_string_literal: true

module Api
  class MeController < ApplicationController
    include ApiAuthenticatable

    def show
      user = current_user
      control = user.control
      boss_nickname = control&.accepted? ? control.boss.nickname : nil

      render json: {
        nickname: user.nickname,
        boss_nickname: boss_nickname,
        role: user.role
      }
    end
  end
end
