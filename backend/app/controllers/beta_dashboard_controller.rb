# frozen_string_literal: true

class BetaDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :set_task, only: [:task, :submit_proof]

  def update_pishock
    p = params.permit(:pishock_enabled, :pishock_username, :pishock_share_code, :pishock_api_key)
    attrs = {
      pishock_enabled: p[:pishock_enabled] == "1",
      pishock_username: p[:pishock_username].to_s.strip.presence,
      pishock_share_code: p[:pishock_share_code].to_s.strip.presence
    }
    attrs[:pishock_api_key] = p[:pishock_api_key] if p[:pishock_api_key].present?
    current_user.update!(attrs)
    redirect_to beta_dashboard_path, notice: "PiShock enregistré."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_dashboard_path, alert: e.record.errors.full_messages.join(", ")
  end

  def test_pishock
    u = current_user.reload
    unless u.pishock_username.present? && u.pishock_share_code.present? && u.pishock_api_key.present?
      redirect_to beta_dashboard_path, alert: "Enregistre d’abord ton username, share code et clé API PiShock."
      return
    end

    case PishockService.test_connection!(user: u)
    when :ok
      redirect_to beta_dashboard_path, notice: "PiShock : compte validé (api.pishock.com) et bip de test OK — vérifie l’appareil ou les logs sur pishock.com."
    when :auth_error
      redirect_to beta_dashboard_path, alert: "PiShock : nom d’utilisateur ou clé API refusés (API publique v1). Vérifie sur pishock.com → Account."
    when :device_error
      redirect_to beta_dashboard_path, alert: "PiShock : compte OK, mais le bip a échoué (share code, revendication PUT /Share, shocker hors ligne ou en pause, …). Voir les logs Rails."
    when :skipped
      redirect_to beta_dashboard_path, alert: "Configuration PiShock incomplète."
    when :error
      redirect_to beta_dashboard_path, alert: "PiShock : erreur réseau ou réponse inattendue. Voir les logs Rails."
    end
  end

  def show
    @control = current_user.control
    @invite_url = control_accept_from_link_url(current_user.nickname)
    @devices = current_user.devices.order(created_at: :desc)
    @tasks = current_user.tasks.recent.includes(:proof_of_completion)
    @chaster_lock = fetch_chaster_lock
    @showcase_qr = generate_showcase_qr
  end

  def task
    # Rendered for proof submission
  end

  def submit_proof
    unless @task.can_submit_proof?
      redirect_to beta_dashboard_path, alert: "Impossible de soumettre une preuve (deadline dépassée ou déjà acceptée)."
      return
    end

    unless params[:text].present? || params[:media].present?
      redirect_to beta_task_path(@task), alert: "La preuve doit contenir du texte ou une image/vidéo."
      return
    end

    proof = @task.proof_of_completion || @task.build_proof_of_completion
    proof.text = params[:text].presence
    if params[:media].present?
      proof.media.purge if proof.media.attached?
      proof.media.attach(params[:media])
    end
    proof.status = "pending"
    proof.reviewed_at = nil
    proof.save!

    redirect_to beta_dashboard_path, notice: "Preuve soumise. En attente de validation."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_task_path(@task), alert: e.record.errors.full_messages.join(", ")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: "Accès réservé aux betas."
  end

  def set_task
    @task = current_user.tasks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to beta_dashboard_path, alert: "Tâche non trouvée."
  end

  def fetch_chaster_lock
    return nil unless current_user.chaster_access_token.present?

    ChasterService.new(current_user).current_lock
  rescue ChasterService::Unauthorized, ChasterService::Error
    nil
  end

  def generate_showcase_qr
    url = showcase_url(current_user.nickname)
    qr = RQRCode::QRCode.new(url, size: 8, level: :m)
    qr.as_svg(module_size: 4, fill: "ffffff", color: "000000")
  end
end
