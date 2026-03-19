# frozen_string_literal: true

module Api
  class ChasterController < ApplicationController
    include ApiAuthenticatable

    def lock
      service = ChasterService.new(current_user)
      lock_info = service.current_lock

      if lock_info.nil?
        render json: { lock: nil }
        return
      end

      render json: {
        lock: {
          id: lock_info[:id],
          title: lock_info[:title],
          end_date: lock_info[:end_date],
          is_frozen: lock_info[:is_frozen],
          remaining_seconds: lock_info[:remaining_seconds],
          display_remaining_time: lock_info[:display_remaining_time]
        }
      }
    rescue ChasterService::Unauthorized
      render json: { error: "Chaster non connecté", lock: nil }, status: :unauthorized
    rescue ChasterService::Error => e
      render json: { error: e.message, lock: nil }, status: :unprocessable_entity
    end
  end
end
