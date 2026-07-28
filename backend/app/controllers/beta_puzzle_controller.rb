# frozen_string_literal: true

class BetaPuzzleController < ApplicationController
  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_puzzle_source!
  before_action :set_session, only: %i[
    show start finish progress_snapshot image
  ]

  def index
    @open_sessions = current_user.puzzle_sessions.open.recent.limit(20)
    @recent_sessions = current_user.puzzle_sessions.where.not(status: PuzzleSession::OPEN_STATUSES).recent.limit(20)
  end

  def create
    result = PuzzleSessionCreator.new(
      user: current_user,
      origin: "self",
      image_source: params[:image_source],
      piece_count: params[:piece_count],
      reference_mode: params[:reference_mode],
      time_limit_seconds: blank_to_nil(params[:time_limit_seconds]),
      leverage_photo_id: params[:leverage_photo_id],
      wallpaper_id: params[:wallpaper_id],
      upload_image: params[:upload_image]
    ).call

    unless result.ok
      redirect_to beta_sources_puzzle_path, alert: create_error_message(result.error)
      return
    end

    redirect_to beta_puzzle_path(result.session)
  end

  def show
    @config = current_user.ensure_puzzle_config!
  end

  def start
    unless @session.assigned? || @session.active?
      return render_json_error(:not_open, :unprocessable_entity)
    end

    @session.mark_active! if @session.assigned?
    PosthogProductAnalytics.puzzle_started(current_user, session: @session)

    render json: session_payload(@session)
  end

  def finish
    unless @session.open?
      return render json: { ok: true, status: @session.status, kind: @session.status }
    end

    result = PuzzleFinisher.new(
      session: @session,
      outcome: params.require(:outcome),
      pieces_placed: params[:pieces_placed],
      piece_positions: params[:piece_positions]
    ).call

    unless result.ok
      return render_json_error(result.error, result.http_status || :unprocessable_entity)
    end

    render json: {
      ok: true,
      status: result.session.status,
      kind: result.kind,
      actions_executed: result.actions_executed
    }
  end

  def progress_snapshot
    unless @session.open? || @session.terminal?
      return render_json_error(:not_found, :not_found)
    end

    file = params.require(:snapshot)
    @session.progress_snapshot.attach(file)
    @session.update!(pieces_placed: [[params[:pieces_placed].to_i, 0].max, @session.pieces_total].min) if params.key?(:pieces_placed)

    render json: { ok: true }
  rescue ActionController::ParameterMissing
    render_json_error(:missing_snapshot, :unprocessable_entity)
  end

  def image
    attachment = @session.display_attachment
    unless @session.display_attachment_present?
      head :not_found
      return
    end

    blob = attachment.respond_to?(:blob) ? attachment.blob : attachment
    variant = blob.variant(
      resize_to_limit: [PuzzleSession::MAX_PUZZLE_IMAGE_SIDE, PuzzleSession::MAX_PUZZLE_IMAGE_SIDE]
    ).processed

    redirect_to rails_blob_path(variant, disposition: "inline"), allow_other_host: true
  rescue StandardError
    redirect_to rails_blob_path(attachment, disposition: "inline"), allow_other_host: true
  end

  private

  def set_session
    @session = current_user.puzzle_sessions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    if request.format.json?
      render_json_error(:not_found, :not_found)
    else
      redirect_to beta_sources_puzzle_path, alert: t("flash.beta.puzzle.not_found")
    end
  end

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.beta.beta_only")
  end

  def require_puzzle_source!
    return if BetaCatalog.new(current_user).source_platform_enabled?("puzzle")

    redirect_to beta_dashboard_path, alert: t("flash.beta.catalog_unavailable")
  end

  def blank_to_nil(value)
    value.presence
  end

  def create_error_message(error)
    key = "flash.beta.puzzle.#{error}"
    I18n.exists?(key) ? t(key) : t("flash.beta.puzzle.create_failed")
  end

  def render_json_error(error, status)
    render json: { ok: false, error: error.to_s }, status: status
  end

  def session_payload(session)
    {
      ok: true,
      id: session.id,
      status: session.status,
      grid_cols: session.grid_cols,
      grid_rows: session.grid_rows,
      piece_count: session.piece_count,
      layout_seed: session.layout_seed,
      reference_mode: session.reference_mode,
      deadline_at: session.deadline_at&.iso8601,
      pieces_placed: session.pieces_placed,
      pieces_total: session.pieces_total,
      image_url: beta_puzzle_image_path(session)
    }
  end
end
