# frozen_string_literal: true

class ShowcaseController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [
    :add_time, :create_session, :update_session, :check_answer, :backdoor_add_time, :backdoor_chaster_lock
  ]

  def show
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta

    @showcase_url = showcase_url(@beta.nickname)
    @showcase_quiz_enabled = @beta.showcase_quiz_enabled
    @showcase_snake_enabled = @beta.showcase_snake_enabled
    @showcase_dino_enabled = @beta.showcase_dino_enabled
    @showcase_tetris_enabled = @beta.showcase_tetris_enabled
    @showcase_backdoor_enabled = @beta.showcase_backdoor_enabled
  end

  def quiz
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_quiz_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @quiz_seconds_per_point = ShowcaseGameConfig.quiz_seconds_per_point_for(@beta)
  end

  def snake
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_snake_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @snake_seconds_per_fruit = ShowcaseGameConfig.snake_seconds_per_fruit_for(@beta)
  end

  def dino
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_dino_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @dino_seconds_per_obstacle = ShowcaseGameConfig.dino_seconds_per_obstacle_for(@beta)
  end

  def tetris
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_tetris_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @tetris_seconds_per_line = ShowcaseGameConfig.tetris_seconds_per_line_for(@beta)
  end

  def backdoor
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_backdoor_enabled

    @showcase_url = showcase_url(@beta.nickname)
  end

  def backdoor_chaster_lock
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta
    return render json: { error: t("showcase.api.unavailable") }, status: 404 unless @beta.showcase_backdoor_enabled

    service = ChasterService.new(@beta)
    lock = service.current_lock
    render json: { lock: lock }
  rescue ChasterService::Unauthorized
    render json: { error: "chaster_unauthorized", lock: nil }, status: 401
  rescue ChasterService::Error
    render json: { error: "chaster_error", lock: nil }, status: 502
  end

  def backdoor_add_time
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta

    payload = backdoor_add_params
    result = BetaEvents::ShowcaseBackdoorAddTime.call(
      beta: @beta,
      days: payload[:days],
      hours: payload[:hours],
      minutes: payload[:minutes],
      player_name: payload[:player_name],
      message: payload[:message]
    )

    render json: result.json_body, status: result.http_status
  end

  def add_time
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta

    requested_game_type = params[:game_type].to_s
    game_kind = case requested_game_type
    when "snake", "dino", "tetris" then requested_game_type
    else "quiz"
    end

    seconds = ShowcaseGameConfig.seconds_for_game(
      @beta,
      game_kind,
      requested_seconds: params[:seconds],
      lines_param: params[:lines]
    )

    result = BetaEvents::ShowcaseGameAddTime.call(
      beta: @beta,
      game_kind: game_kind,
      seconds: seconds,
      lines: params[:lines],
      as_json: request.format.json?
    )

    if result.ok
      return render(json: result.json_body, status: :ok) if result.format_json
      return redirect_to(showcase_path(@beta.nickname), notice: t("flash.showcase.thanks"))
    end

    if result.render_not_found
      return render("not_found", status: :not_found)
    end

    if result.format_json
      render json: result.json_body, status: result.http_status
    else
      redirect_to result.redirect_path, result.flash_kind => result.flash_message
    end
  end

  def create_session
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta

    gt = (params[:game_type].presence || "quiz").to_s
    gt = "quiz" unless %w[quiz snake dino tetris].include?(gt)
    unless ShowcaseGameConfig.game_enabled?(@beta, gt)
      return render json: { error: "Jeu indisponible." }, status: 404
    end

    session = @beta.game_sessions.create!(
      game_type: gt,
      played_at: Time.current,
      score: 0
    )
    notify_args = [ @beta.id, session.id, gt ]
    starter_name = showcase_player_name_from_cookie(@beta)
    notify_args << starter_name if starter_name.present?
    ShowcaseGameStartedNotifyJob.perform_later(*notify_args)
    render json: { id: session.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: 422
  end

  def update_session
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta

    game_session = @beta.game_sessions.find(params[:id])
    unless ShowcaseGameConfig.game_enabled?(@beta, game_session.game_type)
      return render json: { error: "Jeu indisponible." }, status: 404
    end
    permitted = session_params
    incoming_name = permitted[:player_name].presence
    first_name_submission = game_session.player_name.blank? && incoming_name.present?

    game_session.update!(permitted)

    if first_name_submission && game_session.player_name.present?
      catalog = BetaCatalog.new(@beta)
      if catalog.source_enabled_for_event_source?(:showcase_game) && catalog.action_enabled?("pishock")
        intensity = ShowcaseGameConfig.pishock_intensity(game_session.score, @beta)
        duration = game_session.game_type == "tetris" ? [ game_session.score, 15 ].min.clamp(1, 15) : 1
        PishockShockJob.perform_later(@beta.id, intensity, duration)
      end
      ShowcaseBetaNotifyJob.perform_later(
        @beta.id,
        game_session.player_name,
        game_session.score,
        game_session.game_type
      )
    end

    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    return render(json: { error: "Session introuvable." }, status: 404)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: 422
  end

  def questions
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta
    return render json: { error: "Jeu indisponible." }, status: 404 unless @beta.showcase_quiz_enabled

    type = params[:type] || "normal"
    if type == "banco"
      q = QuizQuestion.random_banco
    elsif type == "super_banco"
      q = QuizQuestion.random_super_banco
    else
      difficulties = (params[:difficulties] || "bleu,bleu,bleu,blanc,blanc,rouge").split(",")
      questions = QuizQuestion.random_set(difficulties: difficulties)
      return render json: questions.map { |q| { id: q.id, question: q.display_question, difficulty: q.difficulty } }
    end
    return render(json: { error: "Aucune question." }, status: 404) unless q
    render json: { id: q.id, question: q.display_question, difficulty: q.difficulty }
  end

  def check_answer
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta
    return render json: { error: "Jeu indisponible." }, status: 404 unless @beta.showcase_quiz_enabled

    payload = request.content_type&.include?("json") ? JSON.parse(request.raw_post) : params
    q = QuizQuestion.find_by(id: payload["question_id"] || payload[:question_id])
    return render(json: { error: "Question introuvable." }, status: 404) unless q

    correct = q.correct?(payload["answer"] || payload[:answer])
    render json: { correct: correct }
  end

  LEADERBOARD_MAX = 100
  LEADERBOARD_PER_PAGE_DEFAULT = 10
  LEADERBOARD_PER_PAGE_MAX = 20

  def leaderboard
    @beta = find_beta
    return render(json: { error: t("showcase.api.not_found") }, status: 404) unless @beta

    game_type = params[:game_type].presence || "quiz"
    return render json: { error: "Jeu indisponible." }, status: 404 unless ShowcaseGameConfig.game_enabled?(@beta, game_type)
    sort = params[:sort].to_s == "recent" ? "recent" : "score"
    page = [ params[:page].to_i, 1 ].max
    per_page = params[:per_page].to_i
    per_page = LEADERBOARD_PER_PAGE_DEFAULT if per_page < 1
    per_page = [ per_page, LEADERBOARD_PER_PAGE_MAX ].min

    base = @beta.game_sessions
      .where(game_type: game_type)
      .where.not(player_name: [ nil, "" ])

    ordered = if sort == "recent"
      base.order(played_at: :desc, id: :desc)
    else
      base.order(score: :desc, played_at: :desc, id: :desc)
    end

    all_ids = ordered.limit(LEADERBOARD_MAX).pluck(:id)
    total = all_ids.length
    offset = (page - 1) * per_page
    page_ids = all_ids[offset, per_page] || []
    by_id = page_ids.empty? ? {} : base.where(id: page_ids).index_by(&:id)
    rows = page_ids.filter_map { |id| by_id[id] }

    entries = rows.each_with_index.map do |s, i|
      {
        rank: offset + i + 1,
        player_name: s.player_name,
        score: s.score,
        played_at: s.played_at
      }
    end

    total_pages = total.zero? ? 0 : ((total - 1) / per_page) + 1

    render json: {
      entries: entries,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages,
      sort: sort
    }
  end

  private

  def find_beta
    User.find_by(nickname: params[:nickname], role: :beta)
  end

  def showcase_player_name_from_cookie(beta)
    cookies[showcase_player_cookie_key(beta)].to_s.squish.presence&.truncate(80)
  end

  def showcase_player_cookie_key(beta)
    "bgShowcasePlayer_#{beta.nickname.to_s.gsub(/[^a-zA-Z0-9]/, "_")}"
  end

  def session_params
    params.permit(:score, :player_name).slice(:score, :player_name).compact
  end

  def backdoor_add_params
    params.permit(:days, :hours, :minutes, :player_name, :message)
  end
end
