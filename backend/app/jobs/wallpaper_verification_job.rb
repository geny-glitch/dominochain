# frozen_string_literal: true

class WallpaperVerificationJob < ApplicationJob
  queue_as :wallpaper_verification
  limits_concurrency to: 1, key: ->(sample_id, **) { "wallpaper_verification/#{sample_id}" }

  COMPARE_TIMEOUT = 90.seconds
  DEFER_WAIT = 5.seconds
  MAX_DEFER_ATTEMPTS = 12

  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionFailed, wait: 5.seconds, attempts: 3
  retry_on PG::ConnectionBad, wait: 5.seconds, attempts: 3

  def self.enqueue_for(sample_id)
    if job_pending?(sample_id)
      Rails.logger.info(
        "[WallpaperVerification] action=enqueue_skipped sample=#{sample_id} reason=already_pending"
      )
      return false
    end

    perform_later(sample_id)
    true
  rescue SolidQueue::Job::EnqueueError, ActiveRecord::ActiveRecordError, PG::ConnectionBad => e
    Rails.logger.warn(
      "[WallpaperVerification] action=enqueue_failed sample=#{sample_id} " \
      "#{e.class}: #{e.message}"
    )
    false
  end

  def self.job_pending?(sample_id)
    SolidQueue::Job
      .where(finished_at: nil, class_name: name)
      .where("(arguments::jsonb -> 'arguments' ->> 0) = ?", sample_id.to_s)
      .exists?
  end

  def perform(sample_id, defer_attempt: 0)
    timer = WallpaperVerificationTimer.new(sample_id)
    sample = nil
    wallpaper = nil

    sample = timer.measure(:load_records) do
      DeviceWallpaperSample.includes(device: :wallpapers).find_by(id: sample_id)
    end
    return unless sample&.image&.attached?

    device = sample.device
    wallpaper = device.current_wallpaper
    unless wallpaper&.image&.attached?
      timer.measure(:persist) do
        update_sample!(sample, wallpaper_id: nil, verification_status: "skipped")
      end
      timer.finish(status: "skipped")
      return
    end

    latest_application = device.wallpaper_applications.recent.first
    if latest_application && sample.sampled_at < latest_application.applied_at
      timer.measure(:persist) do
        update_sample!(
          sample,
          wallpaper_id: wallpaper.id,
          verification_status: "inconclusive"
        )
      end
      timer.finish(status: "inconclusive")
      return
    end

    ready = timer.measure(:variants_ready_check) do
      previews_ready?(sample, wallpaper)
    end

    unless ready
      defer_verification(sample_id, sample, wallpaper, timer, defer_attempt)
      return
    end

    # Vips is memory-heavy; release DB pool slots before image work so web requests keep connections.
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)

    result = nil
    Timeout.timeout(COMPARE_TIMEOUT) do
      result = WallpaperScreenshotComparator.new(
        sample: sample,
        wallpaper: wallpaper,
        device: device,
        timer: timer
      ).compare
    end

    timer.measure(:persist) do
      update_sample!(
        sample,
        wallpaper_id: wallpaper.id,
        similarity_score: result.score,
        verification_status: result.status
      )
    end

    timer.finish(
      status: result.status,
      score: result.score,
      ssim: result.ssim,
      dhash: result.dhash_distance
    )
  rescue Timeout::Error
    timer.measure(:persist) { update_sample!(sample, verification_status: "inconclusive") } if sample
    timer.log_action(action: "timeout", reason: "compare_timeout")
  rescue ImagePreviewVariant::PreviewNotReady
    defer_verification(sample_id, sample, wallpaper, timer, defer_attempt) if sample && wallpaper
  rescue Vips::Error, ActiveStorage::FileNotFoundError => e
    Rails.logger.warn("[WallpaperVerification] sample=#{sample_id} failed: #{e.class}: #{e.message}")
    timer.measure(:persist) { update_sample!(sample, verification_status: "inconclusive") } if sample
    timer.log_action(action: "failed", reason: e.class.name)
  end

  private

  def previews_ready?(sample, wallpaper)
    ImagePreviewVariant.preview_variant_processed?(sample.image.blob) &&
      ImagePreviewVariant.preview_variant_processed?(wallpaper.image.blob)
  end

  def defer_verification(sample_id, sample, wallpaper, timer, defer_attempt)
    if defer_attempt >= MAX_DEFER_ATTEMPTS
      timer.measure(:persist) do
        update_sample!(
          sample,
          wallpaper_id: wallpaper.id,
          verification_status: "inconclusive"
        )
      end
      timer.log_action(action: "variants_timeout", reason: "variants_timeout", attempt: defer_attempt)
      return
    end

    timer.log_action(
      action: "deferred",
      wait_ms: DEFER_WAIT.in_milliseconds,
      attempt: defer_attempt + 1
    )
    self.class.set(wait: DEFER_WAIT).perform_later(sample_id, defer_attempt: defer_attempt + 1)
  end

  def update_sample!(sample, **attrs)
    sample.update!(attrs.merge(verified_at: Time.current))
  end
end
