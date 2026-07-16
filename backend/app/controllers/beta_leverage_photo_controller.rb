# frozen_string_literal: true

class BetaLeveragePhotoController < ApplicationController
  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_catalog_source!
  before_action :set_photo, only: %i[
    show original start add_time tlock_blob decrypt_payload destroy
  ]
  before_action :ensure_draft_photo!, only: %i[original start]
  before_action :ensure_active_or_unlocked!, only: %i[tlock_blob decrypt_payload]
  before_action :ensure_active!, only: %i[add_time]

  def index
    @photos = current_user.leverage_photos.not_deleted.newest_first
    @photos.each { |photo| maybe_unlock!(photo) }
  end

  def show
    maybe_unlock!(@photo)
  end

  def upload_new
  end

  def upload
    unless params[:original_image].present? && params[:censored_image].present? && params[:teaser_image].present?
      redirect_to beta_leverage_photo_upload_path, alert: t("flash.beta.leverage_photo.images_required")
      return
    end

    filename = LeveragePhoto.normalized_original_filename(
      params[:original_filename].presence || params[:original_image].original_filename
    )

    photo = current_user.leverage_photos.build(status: "draft", original_filename: filename)
    photo.original_image.attach(params[:original_image])
    photo.censored_image.attach(params[:censored_image])
    photo.teaser_image.attach(params[:teaser_image])
    photo.save!
    photo.original_image.blob.update!(filename: filename) if photo.original_image.attached?
    photo.assert_attachments!

    redirect_to beta_leverage_photo_path(photo), notice: t("flash.beta.leverage_photo.uploaded")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_leverage_photo_upload_path, alert: e.record.errors.full_messages.to_sentence
  end

  def original
    unless @photo.original_image.attached?
      head :not_found
      return
    end

    send_blob(@photo.original_image.blob, disposition: "inline", filename: @photo.download_filename)
  end

  def start
    duration_seconds = params[:duration_seconds].to_i
    locked_until = Time.zone.parse(params[:locked_until].to_s)
    locked_until ||= Time.current + duration_seconds.seconds if duration_seconds.positive?

    LeveragePhotos::StartTimer.new(
      photo: @photo,
      tlock_blob: params.require(:tlock_blob),
      drand_round: params.require(:drand_round),
      locked_until: locked_until,
      duration_seconds: duration_seconds,
      chain_hash: params[:drand_chain_hash]
    ).call!

    respond_to do |format|
      format.json { render json: { status: "active", locked_until: @photo.reload.locked_until.iso8601 } }
      format.html { redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.timer_started") }
    end
  rescue LeveragePhotos::StartTimer::Error, ActionController::ParameterMissing => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to beta_leverage_photo_path(@photo), alert: e.message }
    end
  end

  def add_time
    locked_until = Time.zone.parse(params.require(:locked_until).to_s)
    added_seconds = params.require(:added_seconds).to_i

    LeveragePhotos::AddTime.new(
      photo: @photo,
      tlock_blob: params.require(:tlock_blob),
      drand_round: params.require(:drand_round),
      locked_until: locked_until,
      added_seconds: added_seconds
    ).call!

    respond_to do |format|
      format.json { render json: { status: "active", locked_until: @photo.reload.locked_until.iso8601, layers: @photo.tlock_layer_count } }
      format.html { redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.time_added") }
    end
  rescue LeveragePhotos::AddTime::Error, ActionController::ParameterMissing => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to beta_leverage_photo_path(@photo), alert: e.message }
    end
  end

  def tlock_blob
    send_tlock_blob!
  end

  def decrypt_payload
    maybe_unlock!(@photo)
    unless @photo.unlocked? || (@photo.active? && @photo.unlock_due?)
      head :forbidden
      return
    end

    @photo.mark_unlocked! if @photo.active? && @photo.unlock_due?
    send_tlock_blob!
  end

  def destroy
    @photo.permanently_delete!
    redirect_to beta_leverage_photos_path, notice: t("flash.beta.leverage_photo.deleted")
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.beta.beta_only")
  end

  def require_catalog_source!
    return if BetaCatalog.new(current_user).source_platform_enabled?("leverage_photo")

    redirect_to beta_settings_path, alert: t("flash.beta.catalog_unavailable")
  end

  def set_photo
    @photo = current_user.leverage_photos.not_deleted.find_by(id: params[:id])
    return if @photo.present?

    redirect_to beta_leverage_photos_path, alert: t("flash.beta.leverage_photo.not_found")
  end

  def ensure_draft_photo!
    return if @photo.draft?

    head :forbidden
  end

  def ensure_active!
    maybe_unlock!(@photo)
    return if @photo.active?

    head :forbidden
  end

  def ensure_active_or_unlocked!
    maybe_unlock!(@photo)
    return if @photo.active? || @photo.unlocked?

    head :forbidden
  end

  def maybe_unlock!(photo = @photo)
    return unless photo&.unlock_due?

    photo.mark_unlocked!
  end

  def send_tlock_blob!
    unless @photo.tlock_blob.attached?
      head :not_found
      return
    end

    send_blob(@photo.tlock_blob.blob, disposition: "attachment", filename: "leverage_photo.tlock")
  end

  def send_blob(blob, disposition:, filename: nil)
    blob.open do |file|
      send_data file.read,
        type: blob.content_type.presence || "application/octet-stream",
        disposition: disposition,
        filename: filename || blob.filename.to_s
    end
  end
end
