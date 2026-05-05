# frozen_string_literal: true

class ShowcaseController < ApplicationController
  # Temps ajouté au verrou par action de score — appliqué côté serveur dans #add_time.
  QUIZ_SECONDS_PER_POINT = 1
  SNAKE_SECONDS_PER_FRUIT = 300
  DINO_SECONDS_PER_OBSTACLE = 300
  TETRIS_SECONDS_PER_LINE = 60

  # Backdoor: max duration per submission (aligné avec #add_time)
  BACKDOOR_MAX_SECONDS = 86_400 * 365

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
    @quiz_seconds_per_point = quiz_seconds_per_point_for(@beta)
  end

  def snake
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_snake_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @snake_seconds_per_fruit = snake_seconds_per_fruit_for(@beta)
  end

  def dino
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_dino_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @dino_seconds_per_obstacle = dino_seconds_per_obstacle_for(@beta)
  end

  def tetris
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_tetris_enabled

    @showcase_url = showcase_url(@beta.nickname)
    @tetris_seconds_per_line = tetris_seconds_per_line_for(@beta)
  end

  def backdoor
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta
    return render "not_found", status: :not_found unless @beta.showcase_backdoor_enabled

    @showcase_url = showcase_url(@beta.nickname)
  end

  def backdoor_chaster_lock
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta
    return render json: { error: "Indisponible." }, status: 404 unless @beta.showcase_backdoor_enabled

    service = ChasterService.new(@beta)
    lock = service.current_lock
    render json: { lock: lock }
  rescue ChasterService::Unauthorized
    render json: { error: "chaster_unauthorized", lock: nil }, status: 401
  rescue ChasterService::Error
    render json: { error: "chaster_error", lock: nil }, status: 502
  end

  def backdoor_add_time
    addition = nil
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta
    return render json: { error: "Indisponible." }, status: 404 unless @beta.showcase_backdoor_enabled

    payload = backdoor_add_params
    days = [payload[:days].to_i, 0].max
    hours = [payload[:hours].to_i, 0].max
    minutes = [payload[:minutes].to_i, 0].max
    if hours > 23 || minutes > 59
      return render json: { error: "Durée invalide." }, status: 422
    end

    seconds = days * 86_400 + hours * 3600 + minutes * 60
    unless seconds.positive? && seconds <= BACKDOOR_MAX_SECONDS
      return render json: { error: "Choisis une durée entre 1 minute et 1 an." }, status: 422
    end

    unless ShowcaseAddTimeLimiter.allow?(beta_id: @beta.id, seconds: seconds)
      cap = ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
      return render json: {
        error: "Trop de temps ajouté récemment (max 2 jours / 5 min). Encore #{cap} s possibles.",
        remaining_seconds: cap
      }, status: :too_many_requests
    end

    name = payload[:player_name].to_s.strip
    message = payload[:message].to_s.strip
    if name.blank? || message.blank?
      return render json: { error: "Le nom et le message sont obligatoires." }, status: 422
    end

    addition = @beta.showcase_time_additions.build(
      seconds: seconds,
      player_name: name,
      message: message,
      chaster_applied: false
    )
    unless addition.save
      return render json: { error: addition.errors.full_messages.join(" ") }, status: 422
    end

    service = ChasterService.new(@beta)
    lock = service.current_lock
    unless lock
      addition.update!(chaster_error: "Aucun cadenas Chaster actif.", chaster_applied: false)
      return render json: { error: "Aucun cadenas Chaster actif pour le moment." }, status: 422
    end

    service.add_time_to_lock(lock[:id], seconds)
    ShowcaseAddTimeLimiter.record!(beta_id: @beta.id, seconds: seconds)
    addition.update!(chaster_applied: true, chaster_error: nil)
    ShowcaseBackdoorNotifyJob.perform_later(@beta.id, name, seconds, message)
    render json: {
      ok: true,
      seconds: seconds,
      lock: lock,
      remaining_seconds: ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
    }
  rescue ChasterService::Unauthorized
    addition&.update(chaster_error: "Chaster non connecté", chaster_applied: false) if addition&.persisted?
    render json: { error: "Chaster non connecté côté vitrine." }, status: 401
  rescue ChasterService::Error => e
    if addition&.persisted?
      addition.update(chaster_error: e.message.to_s.truncate(500), chaster_applied: false)
    end
    render json: { error: "Impossible d'ajouter le temps sur Chaster." }, status: 422
  end

  def add_time
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    requested_game_type = params[:game_type].to_s
    game_kind = case requested_game_type
    when "snake", "dino", "tetris" then requested_game_type
    else "quiz"
    end
    unless showcase_game_enabled_for?(@beta, game_kind)
      return (request.format.json? ? (render(json: { error: "Jeu indisponible." }, status: 404)) : render("not_found", status: :not_found))
    end

    seconds = showcase_seconds_for(@beta, game_kind, params[:seconds])
    unless seconds.present? && seconds.positive? && seconds <= 86_400 * 365 # max 1 an
      return (request.format.json? ? (render(json: { error: "Score invalide." }, status: 422)) : redirect_to(showcase_path(@beta.nickname), alert: "Score invalide."))
    end

    unless ShowcaseAddTimeLimiter.allow?(beta_id: @beta.id, seconds: seconds)
      cap = ShowcaseAddTimeLimiter.remaining_capacity(@beta.id)
      msg = "Trop de temps ajouté récemment. Réessaie plus tard (max 2 jours / 5 min). Encore #{cap} s possibles."
      return (request.format.json? ? (render(json: { error: msg }, status: 429)) : redirect_to(showcase_path(@beta.nickname), alert: msg))
    end

    if game_kind == "snake"
      PishockShockJob.perform_later(@beta.id, pishock_intensity(1, @beta), 1)
    elsif game_kind == "tetris"
      lines = params[:lines].to_i.clamp(1, 8)
      PishockShockJob.perform_later(@beta.id, pishock_intensity(lines, @beta), lines)
    end

    service = ChasterService.new(@beta)
    lock = service.current_lock
    unless lock
      return (request.format.json? ? (render(json: { error: "Indisponible." }, status: 422)) : redirect_to(showcase_path(@beta.nickname), alert: "Indisponible pour le moment."))
    end

    service.add_time_to_lock(lock[:id], seconds)
    ShowcaseAddTimeLimiter.record!(beta_id: @beta.id, seconds: seconds)
    request.format.json? ? render(json: { ok: true }) : redirect_to(showcase_path(@beta.nickname), notice: "Merci !")
  rescue ChasterService::Unauthorized
    request.format.json? ? render(json: { error: "Indisponible." }, status: 401) : redirect_to(showcase_path(@beta.nickname), alert: "Indisponible pour le moment.")
  rescue ChasterService::Error
    request.format.json? ? render(json: { error: "Erreur." }, status: 500) : redirect_to(showcase_path(@beta.nickname), alert: "Une erreur s'est produite.")
  end

  def create_session
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    gt = (params[:game_type].presence || "quiz").to_s
    gt = "quiz" unless %w[quiz snake dino tetris].include?(gt)
    unless showcase_game_enabled_for?(@beta, gt)
      return render json: { error: "Jeu indisponible." }, status: 404
    end

    session = @beta.game_sessions.create!(
      game_type: gt,
      played_at: Time.current,
      score: 0
    )
    ShowcaseGameStartedNotifyJob.perform_later(@beta.id, session.id, gt)
    render json: { id: session.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: 422
  end

  def update_session
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    game_session = @beta.game_sessions.find(params[:id])
    unless showcase_game_enabled_for?(@beta, game_session.game_type)
      return render json: { error: "Jeu indisponible." }, status: 404
    end
    permitted = session_params
    incoming_name = permitted[:player_name].presence
    first_name_submission = game_session.player_name.blank? && incoming_name.present?

    game_session.update!(permitted)

    if first_name_submission && game_session.player_name.present?
      intensity = pishock_intensity(game_session.score, @beta)
      duration = game_session.game_type == "tetris" ? [game_session.score, 15].min.clamp(1, 15) : 1
      PishockShockJob.perform_later(@beta.id, intensity, duration)
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
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta
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
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta
    return render json: { error: "Jeu indisponible." }, status: 404 unless @beta.showcase_quiz_enabled

    payload = request.content_type&.include?("json") ? JSON.parse(request.raw_post) : params
    q = QuizQuestion.find_by(id: payload["question_id"] || payload[:question_id])
    return render(json: { error: "Question introuvable." }, status: 404) unless q

    correct = q.correct?(payload["answer"] || payload[:answer])
    render json: { correct: correct }
  end

  # Top N scores enregistrés (pseudo renseigné) pour la vitrine — paginé côté API.
  LEADERBOARD_MAX = 100
  LEADERBOARD_PER_PAGE_DEFAULT = 10
  LEADERBOARD_PER_PAGE_MAX = 20

  def leaderboard
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    game_type = params[:game_type].presence || "quiz"
    return render json: { error: "Jeu indisponible." }, status: 404 unless showcase_game_enabled_for?(@beta, game_type)
    sort = params[:sort].to_s == "recent" ? "recent" : "score"
    page = [params[:page].to_i, 1].max
    per_page = params[:per_page].to_i
    per_page = LEADERBOARD_PER_PAGE_DEFAULT if per_page < 1
    per_page = [per_page, LEADERBOARD_PER_PAGE_MAX].min

    base = @beta.game_sessions
      .where(game_type: game_type)
      .where.not(player_name: [nil, ""])

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

  def snake_seconds_per_fruit_for(beta)
    s = beta.showcase_snake_seconds_per_fruit
    s = SNAKE_SECONDS_PER_FRUIT if s.blank? || s <= 0
    [s, 86_400 * 365].min
  end

  def quiz_seconds_per_point_for(beta)
    s = beta.showcase_quiz_seconds_per_point
    s = QUIZ_SECONDS_PER_POINT if s.blank? || s <= 0
    [s, 86_400 * 365].min
  end

  def dino_seconds_per_obstacle_for(beta)
    s = beta.showcase_dino_seconds_per_obstacle
    s = DINO_SECONDS_PER_OBSTACLE if s.blank? || s <= 0
    [s, 86_400 * 365].min
  end

  def tetris_seconds_per_line_for(beta)
    s = beta.showcase_tetris_seconds_per_line
    s = TETRIS_SECONDS_PER_LINE if s.blank? || s <= 0
    [s, 86_400 * 365].min
  end

  def showcase_seconds_for(beta, game_kind, requested_seconds)
    case game_kind
    when "snake" then snake_seconds_per_fruit_for(beta)
    when "dino" then dino_seconds_per_obstacle_for(beta)
    when "tetris"
      per = tetris_seconds_per_line_for(beta)
      lines = params[:lines].to_i
      if lines.positive?
        lines = [[lines, 1].max, 8].min
        lines * per
      else
        per
      end
    else
      points = requested_seconds&.to_i
      return nil if points.blank?

      points * quiz_seconds_per_point_for(beta)
    end
  end

  def showcase_game_enabled_for?(beta, game_type)
    case game_type.to_s
    when "snake" then beta.showcase_snake_enabled
    when "dino" then beta.showcase_dino_enabled
    when "tetris" then beta.showcase_tetris_enabled
    when "quiz" then beta.showcase_quiz_enabled
    else false
    end
  end

  def pishock_intensity(base, user)
    factor = [user.pishock_intensity_factor.to_f, 0.01].max
    (base * factor).round.clamp(1, 100)
  end

  def session_params
    params.permit(:score, :player_name).slice(:score, :player_name).compact
  end

  def backdoor_add_params
    params.permit(:days, :hours, :minutes, :player_name, :message)
  end
end
