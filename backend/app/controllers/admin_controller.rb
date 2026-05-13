# frozen_string_literal: true

class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @users = User.includes(controls: :beta).order(:nickname)
    @controls = Control.where(status: :accepted).includes(:boss, :beta)
  end

  def release_control
    control = Control.find(params[:control_id])
    control.destroy!
    redirect_to admin_path, notice: t("flash.admin.beta_released", nickname: control.beta.nickname)
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_path, alert: t("flash.admin.control_not_found")
  end

  def invalidate_feature_flags_cache
    BetaCatalog.invalidate_feature_flags_cache!
    redirect_to admin_path, notice: t("flash.admin.feature_flags_cache_invalidated")
  rescue StandardError => e
    Rails.logger.error("[Admin] failed to invalidate feature flags cache: #{e.class}: #{e.message}")
    redirect_to admin_path, alert: t("flash.admin.feature_flags_cache_invalidation_failed")
  end

  private

  def require_admin!
    redirect_to root_path, alert: t("flash.admin.access_denied") unless current_user.admin?
  end

  def settings
    @app_setting = AppSetting.instance
    @app_setting ||= AppSetting.create!(influencer_names: "")
  end

  def update_settings
    @app_setting = AppSetting.instance
    @app_setting ||= AppSetting.create!(influencer_names: "")
    if @app_setting.update(influencer_names: params[:influencer_names])
      WikimediaCommonsService.fetch_and_store_all
      redirect_to admin_settings_path, notice: t("flash.admin.settings_saved")
    else
      render :settings, status: :unprocessable_entity
    end
  end

  def review
    @images = InfluencerImage.visible.order(created_at: :desc).limit(24)
  end

  def review_images
    page = (params[:page] || 1).to_i
    per_page = 24
    offset = (page - 1) * per_page
    images = InfluencerImage.visible.order(created_at: :desc).offset(offset).limit(per_page)
    has_more = InfluencerImage.visible.count > offset + images.size

    render json: {
      html: render_to_string(partial: "admin/review_image", collection: images, as: :image, formats: [:html]),
      has_more: has_more,
      next_page: has_more ? page + 1 : nil
    }
  end

  def review_like
    image = InfluencerImage.visible.find(params[:id])
    image.like!
    render json: { likes_count: image.likes_count }
  end

  def review_dislike
    image = InfluencerImage.visible.find(params[:id])
    image.dislike!
    render json: { dislikes_count: image.dislikes_count }
  end
end
