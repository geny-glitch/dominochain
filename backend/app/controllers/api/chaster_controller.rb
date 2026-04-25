# frozen_string_literal: true

module Api
  class ChasterController < ApplicationController
    include ApiAuthenticatable

    def lock
      service = ChasterService.new(current_user)
      lock_info = service.current_lock
      pishock_enabled = current_user.pishock_enabled

      snake_sec = current_user.showcase_snake_seconds_per_fruit
      snake_sec = ShowcaseController::SNAKE_SECONDS_PER_FRUIT if snake_sec.blank? || snake_sec <= 0

      if lock_info.nil?
        render json: {
          lock: nil,
          pishock_enabled: pishock_enabled,
          showcase_snake_seconds_per_fruit: snake_sec
        }
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
        },
        pishock_enabled: pishock_enabled,
        showcase_snake_seconds_per_fruit: snake_sec
      }
    rescue ChasterService::Unauthorized
      snake_sec = current_user.showcase_snake_seconds_per_fruit
      snake_sec = ShowcaseController::SNAKE_SECONDS_PER_FRUIT if snake_sec.blank? || snake_sec <= 0
      render json: {
        error: "Chaster non connecté",
        lock: nil,
        pishock_enabled: current_user.pishock_enabled,
        showcase_snake_seconds_per_fruit: snake_sec
      }, status: :unauthorized
    rescue ChasterService::Error => e
      snake_sec = current_user.showcase_snake_seconds_per_fruit
      snake_sec = ShowcaseController::SNAKE_SECONDS_PER_FRUIT if snake_sec.blank? || snake_sec <= 0
      render json: {
        error: e.message,
        lock: nil,
        pishock_enabled: current_user.pishock_enabled,
        showcase_snake_seconds_per_fruit: snake_sec
      }, status: :unprocessable_entity
    end

    def locks
      locks = current_user.chaster_locks.history.limit(50)
      render json: {
        locks: locks.map { |l| lock_to_json(l) }
      }
    end

    private

    def lock_to_json(lock)
      remaining = if lock.status == "locked" && !lock.is_frozen && lock.end_date
                   [lock.end_date - Time.current, 0].max.to_i
                 else
                   nil
                 end
      {
        id: lock.chaster_lock_id,
        title: lock.title,
        status: lock.status,
        start_date: lock.start_date&.iso8601,
        end_date: lock.end_date&.iso8601,
        is_frozen: lock.is_frozen,
        unlocked_at: lock.unlocked_at&.iso8601,
        total_duration: lock.total_duration,
        remaining_seconds: remaining
      }
    end
  end
end
