# frozen_string_literal: true

class CornertimeSessionStarter
  Result = Struct.new(:ok, :session, :config, :error, :http_status, keyword_init: true)

  def initialize(user:, client:, device: nil, duration_minutes: nil)
    @user = user
    @client = client.to_s
    @device = device
    @duration_minutes = duration_minutes
  end

  def call
    unless BetaCatalog.new(@user).source_enabled?("cornertime")
      return Result.new(ok: false, error: I18n.t("cornertime.errors.source_disabled"), http_status: :unprocessable_entity)
    end

    unless CornertimeSession::CLIENTS.include?(@client)
      return Result.new(ok: false, error: I18n.t("cornertime.errors.invalid_client"), http_status: :unprocessable_entity)
    end

    planned_seconds = CornertimeSession.seconds_for_minutes(@duration_minutes)
    unless planned_seconds
      return Result.new(
        ok: false,
        error: I18n.t("cornertime.errors.invalid_duration"),
        http_status: :unprocessable_entity
      )
    end

    open_session = @user.cornertime_sessions.open.order(started_at: :desc).first
    CornertimeSessionFinisher.new(session: open_session).call if open_session

    config = @user.ensure_cornertime_config!
    session = @user.cornertime_sessions.create!(
      status: "calibrating",
      client: @client,
      device: @device,
      started_at: Time.current,
      planned_duration_seconds: planned_seconds,
      violation_count: 0
    )

    Result.new(ok: true, session: session, config: config)
  end
end
