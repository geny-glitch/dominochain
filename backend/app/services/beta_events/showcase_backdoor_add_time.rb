# frozen_string_literal: true

module BetaEvents
  class ShowcaseBackdoorAddTime
    Result = Struct.new(:ok, :http_status, :json_body, keyword_init: true)

    def self.call(beta:, days:, hours:, minutes:, player_name:, message:)
      new(beta: beta, days: days, hours: hours, minutes: minutes, player_name: player_name, message: message).call
    end

    def initialize(beta:, days:, hours:, minutes:, player_name:, message:)
      @beta = beta
      @days = days
      @hours = hours
      @minutes = minutes
      @player_name = player_name
      @message = message
    end

    def call
      return Result.new(ok: false, http_status: :not_found, json_body: { error: "Indisponible." }) unless @beta.showcase_backdoor_enabled

      hours = [ @hours.to_i, 0 ].max
      minutes = [ @minutes.to_i, 0 ].max
      if hours > 23 || minutes > 59
        return Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Durée invalide." })
      end

      seconds = @days.to_i * 86_400 + hours * 3600 + minutes * 60
      unless seconds.positive? && seconds <= ShowcaseGameConfig::BACKDOOR_MAX_SECONDS
        return Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Choisis une durée entre 1 minute et 1 an." })
      end

      unless ShowcaseAddTimeLimiter.allow?(beta_id: @beta.id, seconds: seconds)
        cap = ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
        return Result.new(
          ok: false,
          http_status: :too_many_requests,
          json_body: {
            error: "Trop de temps ajouté récemment (max 2 jours / 5 min). Encore #{cap} s possibles.",
            remaining_seconds: cap
          }
        )
      end

      name = @player_name.to_s.strip
      msg = @message.to_s.strip
      if name.blank? || msg.blank?
        return Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Le nom et le message sont obligatoires." })
      end

      addition = @beta.showcase_time_additions.build(
        seconds: seconds,
        player_name: name,
        message: msg,
        chaster_applied: false
      )
      unless addition.save
        return Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: addition.errors.full_messages.join(" ") })
      end

      event = DomainEvent.new(
        beta: @beta,
        source: :showcase_backdoor,
        kind: :time_committed,
        payload: {
          seconds: seconds,
          player_name: name,
          message: msg
        }
      )

      ctx = Context.new(beta: @beta, event: event)
      ctx.addition = addition

      begin
        execution_status = ActionExecutor.new(beta: @beta, event: event, context: ctx).call
        if %i[source_disabled no_enabled_actions].include?(execution_status)
          addition.update!(chaster_applied: false, chaster_error: "Source ou action désactivée.")
          return Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Source ou action désactivée." })
        end
      rescue ActionExecutionStopped => e
        return backdoor_error_response(e.reason, addition, seconds)
      end

      addition.update!(chaster_applied: true, chaster_error: nil)
      ShowcaseBackdoorNotifyJob.perform_later(@beta.id, name, seconds, msg)
      lock = ChasterService.new(@beta).current_lock

      Result.new(
        ok: true,
        http_status: :ok,
        json_body: {
          ok: true,
          seconds: seconds,
          lock: lock,
          remaining_seconds: ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
        }
      )
    end

    private

    def backdoor_error_response(reason, _addition, _seconds)
      case reason
      when :no_chaster_lock
        Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Aucun cadenas Chaster actif pour le moment." })
      when :chaster_unauthorized
        Result.new(ok: false, http_status: :unauthorized, json_body: { error: "Chaster non connecté côté vitrine." })
      when :chaster_error, :missing_seconds
        Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Impossible d'ajouter le temps sur Chaster." })
      else
        Result.new(ok: false, http_status: :unprocessable_entity, json_body: { error: "Impossible d'ajouter le temps sur Chaster." })
      end
    end
  end
end
