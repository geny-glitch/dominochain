# frozen_string_literal: true

class ShowcaseController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:add_time, :create_session, :update_session, :check_answer]

  def show
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta

    @showcase_url = showcase_url(@beta.nickname)
  end

  def quiz
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta

    @showcase_url = showcase_url(@beta.nickname)
  end

  def snake
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "not_found", status: :not_found unless @beta

    @showcase_url = showcase_url(@beta.nickname)
  end

  def add_time
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    seconds = params[:seconds]&.to_i
    unless seconds.present? && seconds.positive? && seconds <= 86_400 * 365 # max 1 an
      return (request.format.json? ? (render(json: { error: "Score invalide." }, status: 422)) : redirect_to(showcase_path(@beta.nickname), alert: "Score invalide."))
    end

    service = ChasterService.new(@beta)
    lock = service.current_lock
    unless lock
      return (request.format.json? ? (render(json: { error: "Indisponible." }, status: 422)) : redirect_to(showcase_path(@beta.nickname), alert: "Indisponible pour le moment."))
    end

    service.add_time_to_lock(lock[:id], seconds)
    request.format.json? ? render(json: { ok: true }) : redirect_to(showcase_path(@beta.nickname), notice: "Merci !")
  rescue ChasterService::Unauthorized
    request.format.json? ? render(json: { error: "Indisponible." }, status: 401) : redirect_to(showcase_path(@beta.nickname), alert: "Indisponible pour le moment.")
  rescue ChasterService::Error => e
    request.format.json? ? render(json: { error: "Erreur." }, status: 500) : redirect_to(showcase_path(@beta.nickname), alert: "Une erreur s'est produite.")
  end

  def create_session
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    session = @beta.game_sessions.create!(
      game_type: params[:game_type] || "quiz",
      played_at: Time.current,
      score: 0
    )
    render json: { id: session.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: 422
  end

  def update_session
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    game_session = @beta.game_sessions.find(params[:id])
    game_session.update!(session_params)
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    return render(json: { error: "Session introuvable." }, status: 404)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: 422
  end

  def questions
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

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

    payload = request.content_type&.include?("json") ? JSON.parse(request.raw_post) : params
    q = QuizQuestion.find_by(id: payload["question_id"] || payload[:question_id])
    return render(json: { error: "Question introuvable." }, status: 404) unless q

    correct = q.correct?(payload["answer"] || payload[:answer])
    render json: { correct: correct }
  end

  def leaderboard
    @beta = find_beta
    return render(json: { error: "Page introuvable." }, status: 404) unless @beta

    sessions = @beta.game_sessions
      .where(game_type: params[:game_type] || "quiz")
      .where.not(player_name: [nil, ""])
      .order(score: :desc)
      .limit(10)

    render json: sessions.map.with_index(1) { |s, i| { rank: i, player_name: s.player_name, score: s.score, played_at: s.played_at } }
  end

  private

  def find_beta
    User.find_by(nickname: params[:nickname], role: :beta)
  end

  def session_params
    params.permit(:score, :player_name).slice(:score, :player_name).compact
  end
end
