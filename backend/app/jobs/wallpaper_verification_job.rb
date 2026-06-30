# frozen_string_literal: true

require "vips"

class WallpaperVerificationJob < ApplicationJob
  queue_as :wallpaper_verification
  limits_concurrency to: 1, key: ->(screenshot_id, **) { "wallpaper_verification/#{screenshot_id}" }

  COMPARE_TIMEOUT = 90.seconds
  DEFER_WAIT = 5.seconds
  MAX_DEFER_ATTEMPTS = 12

  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionFailed, wait: 5.seconds, attempts: 3
  retry_on PG::ConnectionBad, wait: 5.seconds, attempts: 3

  def self.enqueue_for(screenshot_id)
    if job_pending?(screenshot_id)
      Rails.logger.info(
        "[WallpaperVerification] action=enqueue_skipped screenshot=#{screenshot_id} reason=already_pending"
      )
      return false
    end

    perform_later(screenshot_id)
    true
  rescue SolidQueue::Job::EnqueueError, ActiveRecord::ActiveRecordError, PG::ConnectionBad => e
    Rails.logger.warn(
      "[WallpaperVerification] action=enqueue_failed screenshot=#{screenshot_id} " \
      "#{e.class}: #{e.message}"
    )
    false
  end

  def self.job_pending?(screenshot_id)
    SolidQueue::Job
      .where(finished_at: nil, class_name: name)
      .where("(arguments::jsonb -> 'arguments' ->> 0) = ?", screenshot_id.to_s)
      .exists?
  end

  def perform(screenshot_id, defer_attempt: 0)
    timer = WallpaperVerificationTimer.new(screenshot_id)
    screenshot = nil
    wallpaper = nil

    screenshot = timer.measure(:load_records) do
      DeviceScreenshot.includes(device: :wallpapers).find_by(id: screenshot_id)
    end
    return unless screenshot&.image&.attached?

    device = screenshot.device
    wallpaper = device.current_wallpaper
    unless wallpaper&.image&.attached?
      timer.measure(:persist) do
        update_screenshot!(screenshot, wallpaper_id: nil, verification_status: "skipped")
      end
      timer.finish(status: "skipped")
      return
    end

    latest_application = device.wallpaper_applications.recent.first
    if latest_application && screenshot.captured_at < latest_application.applied_at
      timer.measure(:persist) do
        update_screenshot!(
          screenshot,
          wallpaper_id: wallpaper.id,
          verification_status: "inconclusive"
        )
      end
      evaluate_enforcement!(screenshot)
      timer.finish(status: "inconclusive")
      return
    end

    ready = timer.measure(:variants_ready_check) do
      previews_ready?(screenshot, wallpaper)
    end

    unless ready
      defer_verification(screenshot_id, screenshot, wallpaper, timer, defer_attempt)
      return
    end

    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)

    result = nil
    Timeout.timeout(COMPARE_TIMEOUT) do
      result = WallpaperScreenshotComparator.new(
        screenshot: screenshot,
        wallpaper: wallpaper,
        device: device,
        timer: timer
      ).compare
    end

    timer.measure(:persist) do
      update_screenshot!(
        screenshot,
        wallpaper_id: wallpaper.id,
        similarity_score: result.score,
        verification_status: result.status
      )
    end

    evaluate_enforcement!(screenshot)

    timer.finish(
      status: result.status,
      score: result.score,
      ssim: result.ssim,
      dhash: result.dhash_distance
    )
  rescue Timeout::Error
    timer.measure(:persist) { update_screenshot!(screenshot, verification_status: "inconclusive") } if screenshot
    evaluate_enforcement!(screenshot) if screenshot
    timer.log_action(action: "timeout", reason: "compare_timeout")
  rescue ImagePreviewVariant::PreviewNotReady
    defer_verification(screenshot_id, screenshot, wallpaper, timer, defer_attempt) if screenshot && wallpaper
  rescue ActiveStorage::FileNotFoundError, ActiveRecord::RecordNotFound, ::Vips::Error => e
    mark_compare_failed(screenshot, screenshot_id, timer, e)
  end

  private

  def mark_compare_failed(screenshot, screenshot_id, timer, error)
    Rails.logger.warn("[WallpaperVerification] screenshot=#{screenshot_id} failed: #{error.class}: #{error.message}")
    timer.measure(:persist) { update_screenshot!(screenshot, verification_status: "inconclusive") } if screenshot
    evaluate_enforcement!(screenshot) if screenshot
    timer.log_action(action: "failed", reason: error.class.name)
  end

  def previews_ready?(screenshot, wallpaper)
    ImagePreviewVariant.preview_variant_processed?(screenshot.image.blob) &&
      ImagePreviewVariant.preview_variant_processed?(wallpaper.image.blob)
  end

  def defer_verification(screenshot_id, screenshot, wallpaper, timer, defer_attempt)
    if defer_attempt >= MAX_DEFER_ATTEMPTS
      timer.measure(:persist) do
        update_screenshot!(
          screenshot,
          wallpaper_id: wallpaper.id,
          verification_status: "inconclusive"
        )
      end
      evaluate_enforcement!(screenshot)
      timer.log_action(action: "variants_timeout", reason: "variants_timeout", attempt: defer_attempt)
      return
    end

    timer.log_action(
      action: "deferred",
      wait_ms: DEFER_WAIT.in_milliseconds,
      attempt: defer_attempt + 1
    )
    self.class.set(wait: DEFER_WAIT).perform_later(screenshot_id, defer_attempt: defer_attempt + 1)
  end

  def update_screenshot!(screenshot, **attrs)
    screenshot.update!(attrs.merge(verified_at: Time.current))
  end

  def evaluate_enforcement!(screenshot)
    user = screenshot.device.user
    return unless user

    config = user.wallpaper_enforcement_config
    return unless config&.enabled?
    return unless BetaCatalog.new(user).source_enabled?("wallpaper")

    WallpaperEnforcementEvaluator.new(user).evaluate_verification!(screenshot: screenshot)
  end
end
