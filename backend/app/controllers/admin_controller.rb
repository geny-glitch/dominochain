# frozen_string_literal: true

class AdminController < ApplicationController
  def index
    @devices = Device.order(created_at: :desc)
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

  def review_hide
    image = InfluencerImage.find(params[:id])
    image.hide!
    render json: { success: true }
  end
end
