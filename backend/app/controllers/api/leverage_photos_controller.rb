# frozen_string_literal: true

module Api
  class LeveragePhotosController < ApplicationController
    include ApiAuthenticatable

    before_action :require_catalog_action!
    before_action :set_photo, only: %i[
      show censor start add_time tlock_blob original decrypt_payload restore_original set_as_wallpaper
    ]
    before_action :ensure_lockable_for_start!, only: %i[start]
    before_action :ensure_original_access!, only: %i[original]
    before_action :ensure_can_censor!, only: %i[censor]
    before_action :ensure_active_or_unlocked!, only: %i[tlock_blob decrypt_payload]
    before_action :ensure_restorable!, only: %i[restore_original]
    before_action :ensure_active!, only: %i[add_time]

    def index
      photos = current_user.leverage_photos.not_deleted.newest_first
      photos.each { |photo| maybe_unlock!(photo) }
      render json: { photos: LeveragePhotoPayload.list_json(photos, helpers: self) }
    end

    def show
      maybe_unlock!(@photo)
      render json: LeveragePhotoPayload.detail_json(@photo, helpers: self)
    end

    def create
      unless params[:original_image].present? && params[:teaser_image].present?
        render json: { error: I18n.t("flash.beta.leverage_photo.images_required") }, status: :unprocessable_entity
        return
      end

      photo = create_draft_photo!(
        original_image: params[:original_image],
        teaser_image: params[:teaser_image],
        censored_image: params[:censored_image],
        original_filename: params[:original_filename]
      )

      render json: LeveragePhotoPayload.detail_json(photo, helpers: self), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    def censor
      unless params[:censored_image].present?
        render json: { error: I18n.t("flash.beta.leverage_photo.censor_required") }, status: :unprocessable_entity
        return
      end

      @photo.censored_image.attach(params[:censored_image])
      @photo.save!
      @photo.assert_attachments!
      render json: LeveragePhotoPayload.detail_json(@photo, helpers: self)
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
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

      render json: {
        status: "active",
        locked_until: @photo.reload.locked_until.iso8601,
        photo: LeveragePhotoPayload.detail_json(@photo, helpers: self)
      }
    rescue LeveragePhotos::StartTimer::Error, ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
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

      render json: {
        status: "active",
        locked_until: @photo.reload.locked_until.iso8601,
        layers: @photo.tlock_layer_count,
        photo: LeveragePhotoPayload.detail_json(@photo, helpers: self)
      }
    rescue LeveragePhotos::AddTime::Error, ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
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

    def original
      unless @photo.original_image.attached?
        head :not_found
        return
      end

      send_blob(@photo.original_image.blob, disposition: "inline", filename: @photo.download_filename)
    end

    def restore_original
      unless params[:original_image].present?
        render json: { error: I18n.t("flash.beta.leverage_photo.images_required") }, status: :unprocessable_entity
        return
      end

      @photo.persist_restored_original!(params[:original_image])
      render json: {
        status: "unlocked",
        restored: true,
        photo: LeveragePhotoPayload.detail_json(@photo.reload, helpers: self)
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    def set_as_wallpaper
      variant = params[:variant].presence&.to_sym || :display
      LeveragePhotos::ApplyAsWallpaper.new(photo: @photo, user: current_user, variant: variant).call!
      render json: {
        ok: true,
        photo: LeveragePhotoPayload.detail_json(@photo, helpers: self)
      }
    rescue LeveragePhotos::ApplyAsWallpaper::Error => e
      status, message = wallpaper_error(e.message)
      render json: { error: message }, status: status
    end

    private

    def require_catalog_action!
      return if BetaCatalog.new(current_user).action_platform_enabled?("leverage_photo")

      render json: { error: I18n.t("flash.beta.catalog_unavailable") }, status: :forbidden
    end

    def set_photo
      @photo = current_user.leverage_photos.not_deleted.find_by(id: params[:id])
      return if @photo.present?

      render json: { error: I18n.t("flash.beta.leverage_photo.not_found") }, status: :not_found
    end

    def ensure_original_access!
      return if @photo.draft? || (@photo.unlocked? && @photo.original_image.attached?)

      head :forbidden
    end

    def ensure_restorable!
      maybe_unlock!(@photo)
      return if @photo.unlocked? && @photo.tlock_blob.attached? && !@photo.original_image.attached?

      head :forbidden
    end

    def ensure_can_censor!
      return if @photo.can_censor?

      render json: { error: I18n.t("flash.beta.leverage_photo.censor_unavailable") }, status: :unprocessable_entity
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

    def wallpaper_error(code)
      case code
      when "boss controls wallpaper"
        [ :forbidden, I18n.t("flash.beta.wallpaper.boss_controls_wallpaper") ]
      when "verification session locked"
        [ :conflict, I18n.t("flash.beta.wallpaper.verification_session_locked") ]
      when "no device"
        [ :unprocessable_entity, I18n.t("flash.beta.wallpaper.no_device") ]
      when "no displayable image"
        [ :unprocessable_entity, I18n.t("flash.beta.leverage_photo.wallpaper_no_image") ]
      else
        [ :unprocessable_entity, code ]
      end
    end
  end
end
