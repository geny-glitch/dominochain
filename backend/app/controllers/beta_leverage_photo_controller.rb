# frozen_string_literal: true

class BetaLeveragePhotoController < ApplicationController
  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_catalog_action!
  before_action :set_photo, only: %i[
    show original censor_new censor start add_time tlock_blob decrypt_payload destroy set_as_wallpaper
  ]
  before_action :ensure_lockable_for_start!, only: %i[start]
  before_action :ensure_draft_photo!, only: %i[original]
  before_action :ensure_can_censor!, only: %i[censor_new censor]
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
    unless params[:original_image].present? && params[:teaser_image].present?
      respond_to do |format|
        format.json { render json: { error: t("flash.beta.leverage_photo.images_required") }, status: :unprocessable_entity }
        format.html { redirect_to beta_leverage_photo_upload_path, alert: t("flash.beta.leverage_photo.images_required") }
      end
      return
    end

    photo = create_draft_photo!(
      original_image: params[:original_image],
      teaser_image: params[:teaser_image],
      censored_image: params[:censored_image],
      original_filename: params[:original_filename]
    )

    respond_to do |format|
      format.json do
        render json: {
          id: photo.id,
          url: beta_leverage_photo_path(photo),
          censored: photo.censored_image.attached?
        }
      end
      format.html do
        notice =
          if photo.censored_image.attached?
            t("flash.beta.leverage_photo.uploaded")
          else
            t("flash.beta.leverage_photo.uploaded_without_censor")
          end
        redirect_to beta_leverage_photo_path(photo), notice: notice
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.json { render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity }
      format.html { redirect_to beta_leverage_photo_upload_path, alert: e.record.errors.full_messages.to_sentence }
    end
  end

  def censor_new
  end

  def censor
    unless params[:censored_image].present?
      redirect_to beta_leverage_photo_censor_path(@photo), alert: t("flash.beta.leverage_photo.censor_required")
      return
    end

    @photo.censored_image.attach(params[:censored_image])
    @photo.save!
    @photo.assert_attachments!

    redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.censored")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to beta_leverage_photo_censor_path(@photo), alert: e.record.errors.full_messages.to_sentence
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

  def set_as_wallpaper
    LeveragePhotos::ApplyAsWallpaper.new(photo: @photo, user: current_user).call!
    redirect_back fallback_location: beta_leverage_photos_path, notice: t("flash.beta.leverage_photo.wallpaper_set")
  rescue LeveragePhotos::ApplyAsWallpaper::Error => e
    alert =
      case e.message
      when "boss controls wallpaper"
        t("flash.beta.wallpaper.boss_controls_wallpaper")
      when "no device"
        t("flash.beta.wallpaper.no_device")
      when "no displayable image"
        t("flash.beta.leverage_photo.wallpaper_no_image")
      else
        e.message
      end
    redirect_back fallback_location: beta_leverage_photos_path, alert: alert
  end

  private

  def require_beta_role!
    return if current_user.beta?

    redirect_to dashboard_path, alert: t("flash.beta.beta_only")
  end

  def require_catalog_action!
    return if BetaCatalog.new(current_user).action_platform_enabled?("leverage_photo")

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

  def ensure_can_censor!
    return if @photo.can_censor?

    redirect_to beta_leverage_photo_path(@photo), alert: t("flash.beta.leverage_photo.censor_unavailable")
  end

  def ensure_lockable_for_start!
    return if @photo.can_start_timer?

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

  def create_draft_photo!(original_image:, teaser_image:, original_filename:, censored_image: nil)
    filename = LeveragePhoto.normalized_original_filename(
      original_filename.presence || original_image.original_filename
    )

    photo = current_user.leverage_photos.build(status: "draft", original_filename: filename)
    photo.original_image.attach(original_image)
    photo.teaser_image.attach(teaser_image)
    photo.censored_image.attach(censored_image) if censored_image.present?
    photo.save!
    photo.original_image.blob.update!(filename: filename) if photo.original_image.attached?
    photo.assert_attachments!
    photo
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
