# frozen_string_literal: true

class AdminController < ApplicationController
  WALLPAPER_PAIRS_PER_PAGE = 30

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

  def settings
    @app_setting = AppSetting.instance
    @app_setting ||= AppSetting.create!(influencer_names: "")
  end

  def update_settings
    @app_setting = AppSetting.instance
    @app_setting ||= AppSetting.create!(influencer_names: "")
    if @app_setting.update(
      influencer_names: params[:influencer_names],
      wallpaper_verification_algorithm: params[:wallpaper_verification_algorithm]
    )
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

  def wallpaper_pairs
    @filter = params[:filter].presence || "unreviewed"
    @page = [(params[:page] || 1).to_i, 1].max

    scope = wallpaper_pairs_scope
    @total_count = scope.count
    @total_pages = [(@total_count / WALLPAPER_PAIRS_PER_PAGE.to_f).ceil, 1].max
    @page = [@page, @total_pages].min

    offset = (@page - 1) * WALLPAPER_PAIRS_PER_PAGE
    @pairs = scope.offset(offset).limit(WALLPAPER_PAIRS_PER_PAGE)
    @comparisons_by_screenshot_and_algorithm = wallpaper_algorithm_comparisons_for(@pairs)
    @active_verification_algorithm = AppSetting.wallpaper_verification_algorithm
  end

  def wallpaper_pair_run_algorithm
    screenshot = DeviceScreenshot.labelable.find(params[:id])
    algorithm = params[:algorithm].to_s
    unless AppSetting::WALLPAPER_VERIFICATION_ALGORITHMS.key?(algorithm)
      redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
        alert: t("flash.admin.wallpaper_algorithm_invalid")
      return
    end

    WallpaperAlgorithmComparisonRunner.new(screenshot: screenshot, algorithm: algorithm).run!

    redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
      notice: t("flash.admin.wallpaper_algorithm_ran", algorithm: AppSetting::WALLPAPER_VERIFICATION_ALGORITHMS.fetch(algorithm))
  rescue WallpaperAlgorithmComparisonRunner::PreviewNotReady
    redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
      alert: t("flash.admin.wallpaper_algorithm_preview_not_ready")
  rescue WallpaperAlgorithmComparisonRunner::CompareTimeout
    redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
      alert: t("flash.admin.wallpaper_algorithm_timeout")
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
    Rails.logger.error("[Admin] wallpaper algorithm comparison failed screenshot=#{screenshot&.id}: #{e.class}: #{e.message}")
    redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
      alert: t("flash.admin.wallpaper_algorithm_failed")
  rescue StandardError => e
    Rails.logger.error("[Admin] wallpaper algorithm comparison failed screenshot=#{screenshot&.id}: #{e.class}: #{e.message}")
    redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
      alert: t("flash.admin.wallpaper_algorithm_failed")
  end

  def wallpaper_pairs_export_disagreements
    exported = WallpaperPairsDatasetExporter.new.export_disagreements!
    redirect_to admin_wallpaper_pairs_path(filter: "disagreements"),
      notice: t("flash.admin.wallpaper_disagreements_exported", count: exported.size)
  end

  def wallpaper_pair_review
    screenshot = DeviceScreenshot.labelable.find(params[:id])
    expected_status = params[:expected_status].to_s
    unless WallpaperPairReview::EXPECTED_STATUSES.include?(expected_status)
      redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
        alert: t("flash.admin.wallpaper_pair_invalid_status")
      return
    end

    review = WallpaperPairReview.find_or_initialize_by(device_screenshot: screenshot)
    review.assign_attributes(
      wallpaper_id: screenshot.wallpaper_id,
      expected_status: expected_status,
      reviewed_by: current_user,
      reviewed_at: Time.current
    )
    review.save!

    redirect_to admin_wallpaper_pairs_path(filter: params[:filter], page: params[:page]),
      notice: t("flash.admin.wallpaper_pair_reviewed", status: t("admin_wallpaper_pairs.status.#{expected_status}"))
  end

  private

  def require_admin!
    redirect_to root_path, alert: t("flash.admin.access_denied") unless current_user.admin?
  end

  def wallpaper_pairs_scope
    scope = DeviceScreenshot.labelable
      .includes(
        :device,
        :wallpaper,
        :wallpaper_pair_review,
        :wallpaper_algorithm_comparisons,
        image_attachment: :blob,
        wallpaper: { image_attachment: :blob }
      )
      .order(captured_at: :desc)

    scope = scope.unreviewed if @filter == "unreviewed"
    scope = scope.disagreeing_with_local_match if @filter == "disagreements"
    scope
  end

  def wallpaper_algorithm_comparisons_for(pairs)
    screenshot_ids = pairs.map(&:id)
    return {} if screenshot_ids.empty?

    WallpaperAlgorithmComparison
      .where(device_screenshot_id: screenshot_ids)
      .index_by { |comparison| [comparison.device_screenshot_id, comparison.algorithm] }
  end
end
