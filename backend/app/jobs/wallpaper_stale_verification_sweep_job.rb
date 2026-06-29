# frozen_string_literal: true

class WallpaperStaleVerificationSweepJob < ApplicationJob
  STALE_PENDING_AFTER = 15.seconds

  def perform(device_id)
    device = Device.find_by(id: device_id)
    return unless device

    device.device_screenshots
      .where(verification_status: "pending")
      .where(created_at: ...STALE_PENDING_AFTER.ago)
      .pluck(:id)
      .each { |screenshot_id| enqueue_verification(screenshot_id) }
  end

  private

  def enqueue_verification(screenshot_id)
    WallpaperVerificationJob.perform_later(screenshot_id)
  rescue SolidQueue::Job::EnqueueError, ActiveRecord::ActiveRecordError, PG::ConnectionBad => e
    Rails.logger.warn(
      "[WallpaperStaleVerificationSweep] screenshot=#{screenshot_id} enqueue failed: #{e.class}: #{e.message}"
    )
  end
end
