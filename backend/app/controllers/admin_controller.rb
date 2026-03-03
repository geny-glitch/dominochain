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
    redirect_to admin_path, notice: "Beta #{control.beta.nickname} libéré."
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_path, alert: "Control non trouvé."
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Accès refusé." unless current_user.admin?
  end

  def settings
    @app_setting = AppSetting.instance
  end

  def update_settings
    @app_setting = AppSetting.instance
    if @app_setting.update(influencer_names: params[:influencer_names])
      WikimediaCommonsService.fetch_and_store_all
      redirect_to admin_settings_path, notice: "Liste enregistrée. Images récupérées."
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
