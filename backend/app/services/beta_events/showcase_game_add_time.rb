# frozen_string_literal: true

module BetaEvents
  # HTTP-agnostic orchestration for vitrine POST add_time; controller maps Result to response.
  class ShowcaseGameAddTime
    Result = Struct.new(
      :ok,
      :format_json,
      :http_status,
      :json_body,
      :redirect_path,
      :flash_kind,
      :flash_message,
      :render_not_found,
      keyword_init: true
    )

    def self.call(beta:, game_kind:, seconds:, lines: nil, as_json: false)
      new(beta: beta, game_kind: game_kind, seconds: seconds, lines: lines, as_json: as_json).call
    end

    def initialize(beta:, game_kind:, seconds:, lines:, as_json:)
      @beta = beta
      @game_kind = game_kind.to_s
      @seconds = seconds
      @lines = lines
      @as_json = as_json
    end

    def call
      unless ShowcaseGameConfig.game_enabled?(@beta, @game_kind)
        return game_disabled_result
      end

      unless @seconds.present? && @seconds.to_i.positive? && @seconds <= ShowcaseGameConfig::BACKDOOR_MAX_SECONDS
        return failure(:unprocessable_entity, "Score invalide.")
      end

      sec = @seconds.to_i
      unless ShowcaseAddTimeLimiter.allow?(beta_id: @beta.id, seconds: sec)
        cap = ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
        msg = "Trop de temps ajouté récemment. Réessaie plus tard (max 2 jours / 5 min). Encore #{cap} s possibles."
        return rate_limited(msg, cap)
      end

      event = DomainEvent.new(
        beta: @beta,
        source: :showcase_game,
        kind: :score_time_applied,
        payload: {
          seconds: sec,
          game_kind: @game_kind,
          lines: @lines
        }
      )

      ActionExecutor.new(beta: @beta, event: event).call

      Result.new(
        ok: true,
        format_json: @as_json,
        http_status: :ok,
        json_body: { ok: true },
        redirect_path: nil,
        flash_kind: nil,
        flash_message: nil,
        render_not_found: false
      )
    rescue ActionExecutionStopped => e
      map_chaster_stopped(e.reason)
    end

    private

    def game_disabled_result
      if @as_json
        failure(:not_found, "Jeu indisponible.")
      else
        Result.new(
          ok: false,
          format_json: false,
          http_status: :not_found,
          json_body: nil,
          redirect_path: nil,
          flash_kind: nil,
          flash_message: nil,
          render_not_found: true
        )
      end
    end

    def failure(status, message)
      Result.new(
        ok: false,
        format_json: @as_json,
        http_status: status,
        json_body: { error: message },
        redirect_path: showcase_path(@beta.nickname),
        flash_kind: :alert,
        flash_message: message,
        render_not_found: false
      )
    end

    def rate_limited(message, cap)
      if @as_json
        Result.new(
          ok: false,
          format_json: true,
          http_status: :too_many_requests,
          json_body: { error: message, remaining_seconds: cap },
          redirect_path: nil,
          flash_kind: nil,
          flash_message: nil,
          render_not_found: false
        )
      else
        Result.new(
          ok: false,
          format_json: false,
          http_status: :ok,
          json_body: nil,
          redirect_path: showcase_path(@beta.nickname),
          flash_kind: :alert,
          flash_message: message,
          render_not_found: false
        )
      end
    end

    def map_chaster_stopped(reason)
      case reason
      when :no_chaster_lock
        if @as_json
          failure(:unprocessable_entity, "Indisponible.")
        else
          Result.new(ok: false, format_json: false, http_status: :ok, json_body: nil,
            redirect_path: showcase_path(@beta.nickname), flash_kind: :alert, flash_message: "Indisponible pour le moment.",
            render_not_found: false)
        end
      when :chaster_unauthorized
        if @as_json
          failure(:unauthorized, "Indisponible.")
        else
          Result.new(ok: false, format_json: false, http_status: :ok, json_body: nil,
            redirect_path: showcase_path(@beta.nickname), flash_kind: :alert, flash_message: "Indisponible pour le moment.",
            render_not_found: false)
        end
      when :chaster_error, :missing_seconds
        if @as_json
          failure(:internal_server_error, "Erreur.")
        else
          Result.new(ok: false, format_json: false, http_status: :ok, json_body: nil,
            redirect_path: showcase_path(@beta.nickname), flash_kind: :alert, flash_message: "Une erreur s'est produite.",
            render_not_found: false)
        end
      else
        failure(:internal_server_error, "Erreur.")
      end
    end

    def showcase_path(nickname)
      Rails.application.routes.url_helpers.showcase_path(nickname)
    end
  end
end
