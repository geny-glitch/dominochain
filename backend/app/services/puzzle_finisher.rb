# frozen_string_literal: true

# Ends an open puzzle session and applies configured scenario sanctions.
class PuzzleFinisher
  Result = Struct.new(
    :ok,
    :session,
    :kind,
    :actions_executed,
    :error,
    :http_status,
    keyword_init: true
  )

  OUTCOMES = {
    "complete" => :complete,
    "completed" => :complete,
    "abandon" => :abandon,
    "abandoned" => :abandon,
    "timeout" => :timeout,
    "failed_time" => :timeout
  }.freeze

  def initialize(session:, outcome:, pieces_placed: nil, piece_positions: nil, at: Time.current)
    @session = session
    @user = session.user
    @outcome = OUTCOMES[outcome.to_s] || outcome.to_sym
    @pieces_placed = pieces_placed
    @piece_positions = piece_positions
    @at = at
  end

  def call
    unless @session.open?
      return Result.new(
        ok: true,
        session: @session,
        kind: terminal_kind_for(@session.status),
        actions_executed: []
      )
    end

    kind = resolve_kind!
    status = status_for(kind)

    if kind == "completed" || kind == "completed_in_time"
      unless valid_completion?
        return Result.new(
          ok: false,
          session: @session,
          kind: nil,
          actions_executed: [],
          error: :invalid_completion,
          http_status: :unprocessable_entity
        )
      end
    end

    pieces_placed = normalize_pieces_placed
    actions = []

    begin
      @session.update!(
        status: status,
        ended_at: @at,
        pieces_placed: pieces_placed
      )

      actions = apply_sanctions!(kind)

      @session.puzzle_session_events.create!(
        kind: kind,
        pieces_placed: pieces_placed,
        pieces_total: @session.pieces_total,
        actions_executed: actions,
        occurred_at: @at
      )

      capture_analytics!(kind)

      Result.new(ok: true, session: @session.reload, kind: kind, actions_executed: actions)
    rescue StandardError => e
      Rails.logger.error("[PuzzleFinisher] #{e.class}: #{e.message}")
      Result.new(
        ok: false,
        session: @session.reload,
        kind: kind,
        actions_executed: [],
        error: :action_failed,
        http_status: :unprocessable_entity
      )
    end
  end

  private

  def resolve_kind!
    case @outcome
    when :abandon
      "abandoned"
    when :timeout
      "failed_time"
    when :complete
      if @session.time_limit_seconds.present?
        @session.completed_in_time?(at: @at) ? "completed_in_time" : "failed_time"
      else
        "completed"
      end
    else
      raise ArgumentError, "unknown outcome #{@outcome}"
    end
  end

  def status_for(kind)
    case kind
    when "completed", "completed_in_time" then "completed"
    when "failed_time" then "failed_time"
    when "abandoned" then "abandoned"
    else "abandoned"
    end
  end

  def terminal_kind_for(status)
    case status
    when "completed" then "completed"
    when "failed_time" then "failed_time"
    when "abandoned" then "abandoned"
    end
  end

  def valid_completion?
    return false unless @piece_positions.is_a?(Array)
    return false unless @piece_positions.size == @session.pieces_total

    expected = (0...@session.pieces_total).to_a
    positions = @piece_positions.map(&:to_i)
    return false unless positions.sort == expected

    # Grid MVP: piece i must be in cell i when complete.
    positions.each_with_index.all? { |cell, piece_index| cell == piece_index }
  end

  def normalize_pieces_placed
    if @pieces_placed.present?
      [[@pieces_placed.to_i, 0].max, @session.pieces_total].min
    elsif @outcome == :complete && valid_completion?
      @session.pieces_total
    else
      @session.pieces_placed
    end
  end

  def apply_sanctions!(kind)
    unless BetaCatalog.new(@user).source_enabled?("puzzle")
      return []
    end

    config = @user.ensure_puzzle_config!
    scenario = config.scenario_for(kind)
    return [] if scenario.nil?

    allowed = BetaEvents::SourceRegistry.allowed_for(:puzzle, kind)
    sanction = scenario.to_sanction_set(allowed: allowed)
    return [] unless sanction.any_active?

    BetaEvents::SanctionApplier.new(
      beta: @user,
      source: :puzzle,
      kind_map: PuzzleConfig.kind_map_for(kind)
    ).apply!(
      sanction,
      metadata: {
        "puzzle_session_id" => @session.id,
        "pieces_placed" => @session.pieces_placed,
        "pieces_total" => @session.pieces_total,
        "image_source" => @session.image_source,
        "leverage_photo_id" => @session.leverage_photo_id
      }.compact
    )
  end

  def capture_analytics!(kind)
    PosthogProductAnalytics.puzzle_finished(
      @user,
      kind: kind,
      pieces_placed: @session.pieces_placed,
      pieces_total: @session.pieces_total
    )
  rescue StandardError
    nil
  end
end
