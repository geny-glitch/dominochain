# frozen_string_literal: true

module CornertimePayload
  module_function

  def config_json(config)
    config.client_config_payload.merge(
      source_enabled: BetaCatalog.new(config.user).source_enabled?("cornertime")
    )
  end

  def session_json(session)
    {
      id: session.id,
      status: session.status,
      client: session.client,
      started_at: session.started_at&.iso8601,
      ended_at: session.ended_at&.iso8601,
      violation_count: session.violation_count
    }
  end

  def violation_json(violation)
    {
      id: violation.id,
      status: violation.status,
      detected_at: violation.detected_at&.iso8601,
      motion_score: violation.motion_score,
      actions_executed: violation.actions_executed
    }
  end
end
