# frozen_string_literal: true

class BetaLeveragePhotoController < ApplicationController
  layout "beta_dashboard"

  before_action :authenticate_user!
  before_action :require_beta_role!
  before_action :require_catalog_action!
  before_action :set_photo, only: %i[
    show original censor_new censor start add_time tlock_blob decrypt_payload restore_original delete_original destroy set_as_wallpaper
  ]
  before_action :ensure_lockable_for_start!, only: %i[start]
  before_action :ensure_original_access!, only: %i[original]
    before_action :ensure_can_attach_censored!, only: %i[censor_new censor]
  before_action :ensure_active_or_unlocked!, only: %i[tlock_blob decrypt_payload]
  before_action :ensure_restorable!, only: %i[restore_original]
  before_action :ensure_can_delete_original!, only: %i[delete_original]
  before_action :ensure_active!, only: %i[add_time]

  def index
    @list_sort = LeveragePhoto.normalize_list_sort(params[:sort])
    @photos = LeveragePhoto.for_user_list(current_user, sort: @list_sort)
    @photos.each { |photo| photo.bundle_mates.each { |mate| maybe_unlock!(mate) } }
  end

  def show
    @photo.bundle_mates.each { |photo| maybe_unlock!(photo) }
  end

  def upload_new
  end

  def upload
    unless params[:original_image].present? && (params[:teaser_image].present? || params[:censored_image].present?)
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
      original_filename: params[:original_filename],
      bundle: find_upload_bundle
    )

    respond_to do |format|
      format.json do
        render json: {
          id: photo.id,
          bundle_id: photo.bundle_id,
          url: beta_leverage_photo_path(photo.bundle_mates.first || photo),
          censored: photo.censored_images.attached?
        }
      end
      format.html do
        notice =
          if photo.censored_images.count > 1
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
    files = censor_upload_files
    if files.empty?
      redirect_to beta_leverage_photo_censor_path(@photo), alert: t("flash.beta.leverage_photo.censor_required")
      return
    end

    files.each { |file| @photo.censored_images.attach(file) }
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

    LeveragePhotos::LockBundle.start!(
      photo: @photo,
      duration_seconds: duration_seconds
    )

    respond_to do |format|
      format.json { render json: { status: "active", locked_until: @photo.reload.locked_until.iso8601 } }
      format.html { redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.timer_started") }
    end
  rescue LeveragePhotos::LockBundle::Error => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to beta_leverage_photo_path(@photo), alert: e.message }
    end
  end

  def add_time
    added_seconds = params.require(:added_seconds).to_i
    save_as_base = ActiveModel::Type::Boolean.new.cast(params[:save_as_base])
    apply_next_step = ActiveModel::Type::Boolean.new.cast(params[:apply_next_step])

    LeveragePhotos::LockBundle.add_time!(
      photo: @photo,
      added_seconds: added_seconds,
      save_as_base: save_as_base,
      apply_next_step: apply_next_step
    )

    respond_to do |format|
      format.json { render json: { status: "active", locked_until: @photo.reload.locked_until.iso8601, layers: @photo.tlock_layer_count } }
      format.html { redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.time_added") }
    end
  rescue LeveragePhotos::LockBundle::Error, ActionController::ParameterMissing => e
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

  def restore_original
    if @photo.original_image.attached?
      respond_to do |format|
        format.json { render json: { status: "unlocked", restored: true } }
        format.html { redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.restored") }
      end
      return
    end

    if params[:original_image].present?
      @photo.persist_restored_original!(params[:original_image])
    else
      LeveragePhotos::RestorePayload.call!(@photo)
    end

    @photo.reload
    restored = @photo.viewable_original?
    respond_to do |format|
      format.json { render json: { status: "unlocked", restored: restored } }
      format.html do
        redirect_to beta_leverage_photo_path(@photo),
          notice: restored ? t("flash.beta.leverage_photo.restored") : nil
      end
    end
  rescue ActiveRecord::RecordInvalid, LeveragePhotos::Envelope::Error, LeveragePhotos::TlockCrypto::Error, LeveragePhotos::RestorePayload::Error, ArgumentError => e
    message = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : t("flash.beta.leverage_photo.restore_failed")
    respond_to do |format|
      format.json { render json: { error: message }, status: :unprocessable_entity }
      format.html { redirect_to beta_leverage_photo_path(@photo), alert: message }
    end
  end

  def delete_original
    @photo.delete_original_from_sanction!
    redirect_to beta_leverage_photo_path(@photo), notice: t("flash.beta.leverage_photo.original_deleted")
  end

  def destroy
    @photo.permanently_delete!
    redirect_to beta_actions_leverage_photo_path, notice: t("flash.beta.leverage_photo.deleted")
  end

  def random
    photo = LeveragePhotos::PickRandom.any(user: current_user)
    if photo.nil?
      redirect_to beta_actions_leverage_photo_path, alert: t("flash.beta.leverage_photo.none_available")
      return
    end

    maybe_unlock!(photo)
    redirect_to beta_leverage_photo_path(photo)
  end

  def blind
    @photo = current_blind_photo
    maybe_unlock!(@photo) if @photo
    @blind = blind_state
    base_seconds = @blind["base_seconds"].to_i
    if base_seconds.positive?
      @add_amount, @add_unit = LeveragePhoto.duration_parts(base_seconds)
    else
      @add_amount = 1
      @add_unit = "days"
    end
  end

  def blind_pick
    photo = LeveragePhotos::PickRandom.lockable(user: current_user, exclude_id: blind_state["photo_id"])
    if photo.nil?
      redirect_to beta_leverage_photo_blind_path, alert: t("flash.beta.leverage_photo.blind_none_lockable")
      return
    end

    maybe_unlock!(photo)
    write_blind_state!(
      "photo_id" => photo.id,
      "added_seconds" => 0,
      "revealed" => false,
      "base_seconds" => 0,
      "step_n" => 0
    )
    redirect_to beta_leverage_photo_blind_path
  end

  def blind_lock
    photo = current_blind_photo
    if photo.nil?
      respond_to do |format|
        format.json { render json: { error: t("flash.beta.leverage_photo.blind_need_pick") }, status: :unprocessable_entity }
        format.html { redirect_to beta_leverage_photo_blind_path, alert: t("flash.beta.leverage_photo.blind_need_pick") }
      end
      return
    end

    maybe_unlock!(photo)
    added_seconds = params[:added_seconds].presence&.to_i || params[:duration_seconds].to_i
    save_as_base = ActiveModel::Type::Boolean.new.cast(params[:save_as_base])
    apply_next_step = ActiveModel::Type::Boolean.new.cast(params[:apply_next_step])

    if photo.can_add_time? || photo.bundle_can_add_time?
      LeveragePhotos::LockBundle.add_time!(
        photo: photo,
        added_seconds: added_seconds,
        save_as_base: save_as_base,
        apply_next_step: apply_next_step
      )
    elsif photo.can_start_timer? || photo.bundle_can_start_timer?
      LeveragePhotos::LockBundle.start!(
        photo: photo,
        duration_seconds: added_seconds
      )
    else
      raise LeveragePhotos::LockBundle::Error, "cannot add time"
    end

    record_blind_add!(added_seconds, save_as_base: save_as_base, apply_next_step: apply_next_step)

    respond_to do |format|
      format.json { render json: { status: "ok" } }
      format.html { redirect_to beta_leverage_photo_blind_path }
    end
  rescue LeveragePhotos::LockBundle::Error => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to beta_leverage_photo_blind_path, alert: e.message }
    end
  end

  def blind_payload
    photo = current_blind_photo
    if photo.nil?
      head :not_found
      return
    end

    maybe_unlock!(photo)
    if photo.original_image.attached? && !photo.active?
      send_blob(photo.original_image.blob, disposition: "inline", filename: photo.download_filename)
    else
      @photo = photo
      send_tlock_blob!
    end
  end

  def blind_preview
    photo = current_blind_photo
    unless photo && blind_revealed?
      head :forbidden
      return
    end

    preview = photo.preferred_censored_attachment
    unless preview.present?
      head :not_found
      return
    end

    send_blob(preview.blob, disposition: "inline")
  end

  def blind_reveal
    photo = current_blind_photo
    if photo.nil?
      redirect_to beta_leverage_photo_blind_path, alert: t("flash.beta.leverage_photo.blind_need_pick")
      return
    end

    write_blind_state!("revealed" => true)
    redirect_to beta_leverage_photo_blind_path
  end

  def set_as_wallpaper
    variant = params[:variant].presence&.to_sym || :display
    LeveragePhotos::ApplyAsWallpaper.new(
      photo: @photo,
      user: current_user,
      variant: variant,
      censored_image_id: params[:censored_image_id]
    ).call!
    redirect_back fallback_location: beta_leverage_photos_path, notice: t("flash.beta.leverage_photo.wallpaper_set")
  rescue LeveragePhotos::ApplyAsWallpaper::Error => e
    alert =
      case e.message
      when "boss controls wallpaper"
        t("flash.beta.wallpaper.boss_controls_wallpaper")
      when "verification session locked"
        t("flash.beta.wallpaper.verification_session_locked")
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
    @photo = current_user.leverage_photos.not_deleted.includes(:leverage_photo_extensions).find_by(id: params[:id])
    return if @photo.present?

    redirect_to beta_leverage_photos_path, alert: t("flash.beta.leverage_photo.not_found")
  end

  def ensure_original_access!
    return if @photo.draft? || (@photo.unlocked? && @photo.viewable_original?)

    head :forbidden
  end

  def ensure_restorable!
    maybe_unlock!(@photo)
    return if @photo.unlocked? && (
      @photo.original_image.attached? ||
      @photo.tlock_blob.attached? ||
      (@photo.envelope_lock? && @photo.encrypted_original.attached?)
    )

    head :forbidden
  end

  def ensure_can_delete_original!
    return if @photo.can_delete_original?

    redirect_to beta_leverage_photo_path(@photo), alert: t("flash.beta.leverage_photo.original_delete_unavailable")
  end

  def ensure_can_attach_censored!
    return if @photo.can_attach_censored?

    redirect_to beta_leverage_photo_path(@photo), alert: t("flash.beta.leverage_photo.censor_unavailable")
  end

  def censor_upload_files
    LeveragePhoto.uploaded_files(params[:censored_image], params[:censored_images])
  end

  def ensure_lockable_for_start!
    return if @photo.bundle_can_start_timer?

    head :forbidden
  end

  def ensure_active!
    maybe_unlock!(@photo)
    @photo.bundle_mates.each { |photo| maybe_unlock!(photo) }
    return if @photo.bundle_can_add_time?

    head :forbidden
  end

  def ensure_active_or_unlocked!
    maybe_unlock!(@photo)
    return if @photo.active? || @photo.unlocked?

    head :forbidden
  end

  def maybe_unlock!(photo = @photo)
    LeveragePhotos::UnlockPhoto.call!(photo)
  end

  def create_draft_photo!(original_image:, teaser_image:, original_filename:, censored_image: nil, bundle: nil)
    filename = LeveragePhoto.normalized_original_filename(
      original_filename.presence || original_image.original_filename
    )

    photo = current_user.leverage_photos.build(status: "draft", original_filename: filename)
    if bundle
      photo.bundle = bundle
      photo.position = bundle.leverage_photos.maximum(:position).to_i + 1
    end
    photo.original_image.attach(original_image)
    # Optional full reminder first, then auto preview — both become censored versions.
    photo.censored_images.attach(censored_image) if censored_image.present?
    photo.censored_images.attach(teaser_image) if teaser_image.present?
    photo.save!
    photo.original_image.blob.update!(filename: filename) if photo.original_image.attached?
    photo.assert_attachments!
    photo
  end

  def find_upload_bundle
    return if params[:bundle_id].blank?

    current_user.leverage_photo_bundles.find_by(id: params[:bundle_id])
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

  BLIND_SESSION_KEY = :leverage_blind_game

  def blind_state
    session[BLIND_SESSION_KEY] || {}
  end

  def write_blind_state!(attrs)
    session[BLIND_SESSION_KEY] = blind_state.stringify_keys.merge(attrs.stringify_keys)
  end

  def current_blind_photo
    id = blind_state["photo_id"]
    return nil if id.blank?

    current_user.leverage_photos.not_deleted.find_by(id: id)
  end

  def blind_revealed?
    ActiveModel::Type::Boolean.new.cast(blind_state["revealed"])
  end

  def record_blind_add!(added_seconds, save_as_base:, apply_next_step:)
    added = added_seconds.to_i
    return if added <= 0

    next_state = {
      "added_seconds" => blind_state["added_seconds"].to_i + added
    }
    if save_as_base || (apply_next_step && blind_state["base_seconds"].to_i <= 0)
      next_state["base_seconds"] = added
      next_state["step_n"] = 1
    elsif apply_next_step
      next_state["step_n"] = blind_state["step_n"].to_i + 1
    end
    write_blind_state!(next_state)
  end
end
