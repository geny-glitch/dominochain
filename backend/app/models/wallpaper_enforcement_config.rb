# frozen_string_literal: true

class WallpaperEnforcementConfig < ApplicationRecord
  MIN_INTERVAL_MINUTES = 1
  MAX_INTERVAL_MINUTES = 24 * 60
  MIN_DELAY_MINUTES = 0
  MAX_DELAY_MINUTES = 7 * 24 * 60
  MIN_UNREACHABLE_MINUTES = 30
  MAX_UNREACHABLE_MINUTES = 7 * 24 * 60
  MIN_CONSECUTIVE_THRESHOLD = 2
  MAX_CONSECUTIVE_THRESHOLD = 10
  MAX_DOUBLE_CHECK_RECHECKS = 3

  SANCTION_MODE_STRICT = "strict"
  SANCTION_MODE_DOUBLE_CHECK = "double_check"
  SANCTION_MODE_CONSECUTIVE_FAILURES = "consecutive_failures"
  SANCTION_MODES = [
    SANCTION_MODE_STRICT,
    SANCTION_MODE_DOUBLE_CHECK,
    SANCTION_MODE_CONSECUTIVE_FAILURES
  ].freeze

  belongs_to :user

  validates :check_interval_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: MIN_INTERVAL_MINUTES, less_than_or_equal_to: MAX_INTERVAL_MINUTES }
  validates :mismatch_delay_minutes, :permissions_lost_delay_minutes, :app_unreachable_delay_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: MIN_DELAY_MINUTES, less_than_or_equal_to: MAX_DELAY_MINUTES }
  validates :app_unreachable_threshold_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: MIN_UNREACHABLE_MINUTES, less_than_or_equal_to: MAX_UNREACHABLE_MINUTES }
  validates :mismatch_sanction_mode, inclusion: { in: SANCTION_MODES }
  validates :mismatch_consecutive_threshold,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_CONSECUTIVE_THRESHOLD,
      less_than_or_equal_to: MAX_CONSECUTIVE_THRESHOLD
    }
  validate :sanctions_are_valid

  scope :due_for_check, lambda { |reference_time = Time.current|
    where(enabled: true).where(
      "last_scheduled_check_at IS NULL OR last_scheduled_check_at + (check_interval_minutes * interval '1 minute') <= ?",
      reference_time
    )
  }

  def mismatch_sanction_object
    WallpaperSanction.from_hash(mismatch_sanction)
  end

  def permissions_lost_sanction_object
    WallpaperSanction.from_hash(permissions_lost_sanction)
  end

  def app_unreachable_sanction_object
    WallpaperSanction.from_hash(app_unreachable_sanction)
  end

  def due_for_scheduled_check?(reference_time = Time.current)
    return false unless enabled?

    return true if last_scheduled_check_at.blank?

    last_scheduled_check_at + check_interval_minutes.minutes <= reference_time
  end

  def reset_mismatch_state!
    update!(
      mismatch_since: nil,
      add_time_sanction_applied_at: nil,
      mismatch_recheck_count: 0,
      mismatch_consecutive_count: 0
    )
  end

  def strict_sanction_mode?
    mismatch_sanction_mode == SANCTION_MODE_STRICT
  end

  def double_check_sanction_mode?
    mismatch_sanction_mode == SANCTION_MODE_DOUBLE_CHECK
  end

  def consecutive_failures_sanction_mode?
    mismatch_sanction_mode == SANCTION_MODE_CONSECUTIVE_FAILURES
  end

  def reset_permissions_lost_state!
    update!(
      permissions_lost_since: nil,
      permissions_lost_sanction_applied_at: nil
    )
  end

  def reset_app_unreachable_state!
    update!(
      app_unreachable_since: nil,
      app_unreachable_sanction_applied_at: nil
    )
  end

  private

  def sanctions_are_valid
    {
      mismatch_sanction: mismatch_sanction,
      permissions_lost_sanction: permissions_lost_sanction,
      app_unreachable_sanction: app_unreachable_sanction
    }.each do |attr, value|
      sanction = WallpaperSanction.from_hash(value)
      if sanction.chaster_add_time_enabled && sanction.chaster_seconds.blank?
        errors.add(attr, :invalid)
      end
      if sanction.leverage_photo_start_enabled && sanction.leverage_photo_start_seconds.blank?
        errors.add(attr, :invalid)
      end
      if sanction.leverage_photo_add_time_enabled && sanction.leverage_photo_add_time_seconds.blank?
        errors.add(attr, :invalid)
      end
    end
  end
end
