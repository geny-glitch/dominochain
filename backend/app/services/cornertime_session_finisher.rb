# frozen_string_literal: true

# Ends an open cornertime session.
# If stopped before the planned duration, applies early_stop sanctions and marks status "stopped".
# Otherwise marks status "completed" with no early-stop sanctions.
class CornertimeSessionFinisher
  Result = Struct.new(
    :ok,
    :session,
    :early_stop,
    :status,
    :actions_executed,
    :error,
    :http_status,
    keyword_init: true
  )

  def initialize(session:)
    @session = session
    @user = session.user
  end

  def call
    unless @session.open?
      return Result.new(
        ok: true,
        session: @session,
        early_stop: false,
        status: @session.status,
        actions_executed: []
      )
    end

    early = @session.early_if_stopped_now?
    actions = []

    begin
      if early
        actions = apply_early_stop_sanctions!
        @session.update!(status: "stopped", ended_at: Time.current)
      else
        @session.update!(status: "completed", ended_at: Time.current)
      end

      Result.new(
        ok: true,
        session: @session,
        early_stop: early,
        status: @session.status,
        actions_executed: actions
      )
    rescue StandardError => e
      Rails.logger.error("[CornertimeSessionFinisher] #{e.class}: #{e.message}")
      @session.update!(status: "stopped", ended_at: Time.current) if @session.open?
      Result.new(
        ok: false,
        session: @session.reload,
        early_stop: early,
        status: @session.status,
        actions_executed: [],
        error: I18n.t("cornertime.errors.action_failed"),
        http_status: :unprocessable_entity
      )
    end
  end

  private

  def apply_early_stop_sanctions!
    unless BetaCatalog.new(@user).source_enabled?("cornertime")
      return []
    end

    config = @user.ensure_cornertime_config!
    sanction = config.early_stop_sanction_object
    return [] unless sanction.any_active?

    BetaEvents::SanctionApplier.new(
      beta: @user,
      source: :cornertime,
      kind_map: CornertimeConfig.kind_map_for(:early_stop)
    ).apply!(
      sanction,
      metadata: {
        "session_id" => @session.id,
        "planned_duration_seconds" => @session.planned_duration_seconds,
        "elapsed_seconds" => (Time.current - @session.started_at).to_i
      }.compact
    )
  end
end
