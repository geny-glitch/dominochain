# frozen_string_literal: true

module Api
  class ChasterController < ApplicationController
    include ApiAuthenticatable

    def lock
      service = ChasterService.new(current_user)
      lock_info = service.current_lock
      pishock_enabled = current_user.pishock_enabled

      game_seconds = showcase_game_seconds

      if lock_info.nil?
        render json: {
          lock: nil,
          pishock_enabled: pishock_enabled,
          **game_seconds
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
        **game_seconds
      }
    rescue ChasterService::Unauthorized
      game_seconds = showcase_game_seconds
      render json: {
        error: "Chaster non connecté",
        lock: nil,
        pishock_enabled: current_user.pishock_enabled,
        **game_seconds
      }, status: :unauthorized
    rescue ChasterService::Error => e
      game_seconds = showcase_game_seconds
      render json: {
        error: e.message,
        lock: nil,
        pishock_enabled: current_user.pishock_enabled,
        **game_seconds
      }, status: :unprocessable_entity
    end

    def locks
      locks = current_user.chaster_locks.history.limit(50)
      render json: {
        locks: locks.map { |l| lock_to_json(l) }
      }
    end

    def time_events
      page = pagination_page
      per_page = pagination_per_page
      scope = current_user.chaster_time_events.recent
      total_count = scope.count
      events = scope.offset((page - 1) * per_page).limit(per_page)

      render json: {
        events: events.map { |event| time_event_to_json(event) },
        meta: {
          page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count.to_f / per_page).ceil,
          next_page: page * per_page < total_count ? page + 1 : nil
        }
      }
    end

    def add_time
      seconds = params[:seconds].to_i
      service = ChasterService.new(current_user)
      lock_info = service.current_lock
      return render json: { error: "Aucun lock actif" }, status: :unprocessable_entity if lock_info.nil?

      service.add_time_to_lock(
        lock_info[:id],
        seconds,
        source: current_device.present? ? "api" : "puryfi",
        summary: current_device.present? ? "Ajout depuis l'app" : "Ajout depuis PuryFi"
      )
      render json: {
        ok: true,
        added_seconds: seconds,
        lock_id: lock_info[:id]
      }
    rescue ChasterService::Unauthorized
      render json: { error: "Chaster non connecté" }, status: :unauthorized
    rescue ChasterService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def showcase_game_seconds
      quiz_sec = current_user.showcase_quiz_seconds_per_point
      quiz_sec = ShowcaseController::QUIZ_SECONDS_PER_POINT if quiz_sec.blank? || quiz_sec <= 0
      snake_sec = current_user.showcase_snake_seconds_per_fruit
      snake_sec = ShowcaseController::SNAKE_SECONDS_PER_FRUIT if snake_sec.blank? || snake_sec <= 0
      dino_sec = current_user.showcase_dino_seconds_per_obstacle
      dino_sec = ShowcaseController::DINO_SECONDS_PER_OBSTACLE if dino_sec.blank? || dino_sec <= 0
      tetris_sec = current_user.showcase_tetris_seconds_per_line
      tetris_sec = ShowcaseController::TETRIS_SECONDS_PER_LINE if tetris_sec.blank? || tetris_sec <= 0

      {
        showcase_quiz_seconds_per_point: quiz_sec,
        showcase_snake_seconds_per_fruit: snake_sec,
        showcase_dino_seconds_per_obstacle: dino_sec,
        showcase_tetris_seconds_per_line: tetris_sec
      }
    end

    def pagination_page
      page = params.fetch(:page, 1).to_i
      page.positive? ? page : 1
    end

    def pagination_per_page
      per_page = params.fetch(:per_page, 20).to_i
      per_page = 20 unless per_page.positive?
      [per_page, 50].min
    end

    def time_event_to_json(event)
      {
        id: event.id,
        lock_id: event.chaster_lock_id,
        seconds: event.seconds,
        source: event.source,
        source_label: source_label(event.source),
        summary: event.summary,
        occurred_at: event.occurred_at&.iso8601
      }
    end

    def source_label(source)
      {
        "api" => "App/API",
        "puryfi" => "PuryFi",
        "cigarettes" => "Cigarettes",
        "showcase_backdoor" => "Backdoor",
        "showcase_game" => "Vitrine",
        "strava_goal" => "Strava"
      }.fetch(source, source.to_s.humanize)
    end

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
