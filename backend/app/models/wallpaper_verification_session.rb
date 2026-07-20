# frozen_string_literal: true

class WallpaperVerificationSession < ApplicationRecord
  STATUSES = %w[active completed expired].freeze
  ACTIVE_STATUS = "active"
  ALLOWED_DURATION_HOURS = [1, 2, 4, 8, 12, 24].freeze

  belongs_to :user
  belongs_to :device
  belongs_to :wallpaper

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, :ends_at, presence: true
  validates :config_snapshot, presence: true
  validate :ends_at_after_started_at
  validate :only_one_active_session_per_user, on: :create

  scope :recent, -> { order(started_at: :desc, id: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUS).where("ends_at > ?", Time.current) }

  def active?
    status == ACTIVE_STATUS && ends_at.present? && ends_at > Time.current
  end

  def duration_hours
    return nil if started_at.blank? || ends_at.blank?

    ((ends_at - started_at) / 1.hour).round
  end

  def remaining_seconds(at: Time.current)
    return 0 unless active?

    [(ends_at - at).ceil, 0].max
  end

  def expire_if_due!(at: Time.current)
    return false unless status == ACTIVE_STATUS
    return false if ends_at > at

    update!(status: "expired")
    true
  end

  def complete!
    return unless status == ACTIVE_STATUS

    update!(status: "completed")
  end

  def self.expire_due!(at: Time.current)
    where(status: ACTIVE_STATUS).where("ends_at <= ?", at).find_each do |session|
      session.update!(status: "expired")
    end
  end

  def self.seconds_for_hours(hours)
    hours = hours.to_i
    return nil unless ALLOWED_DURATION_HOURS.include?(hours)

    hours * 3600
  end

  def self.build_config_snapshot(config)
    {
      "scenarios" => config.scenarios,
      "check_interval_minutes" => config.check_interval_minutes,
      "dismiss_apps_before_capture" => config.dismiss_apps_before_capture,
      "mismatch_delay_minutes" => config.mismatch_delay_minutes,
      "mismatch_sanction_mode" => config.mismatch_sanction_mode,
      "mismatch_consecutive_threshold" => config.mismatch_consecutive_threshold,
      "permissions_lost_delay_minutes" => config.permissions_lost_delay_minutes,
      "app_unreachable_delay_minutes" => config.app_unreachable_delay_minutes,
      "app_unreachable_threshold_minutes" => config.app_unreachable_threshold_minutes
    }
  end

  def enforcement_snapshot
    WallpaperEnforcementSnapshot.new(config: user.wallpaper_enforcement_config, session: self)
  end

  private

  def ends_at_after_started_at
    return if started_at.blank? || ends_at.blank?
    return if ends_at > started_at

    errors.add(:ends_at, :after, message: "must be after started_at")
  end

  def only_one_active_session_per_user
    return unless status == ACTIVE_STATUS
    return unless user&.wallpaper_verification_sessions&.active&.where&.not(id: id)&.exists?

    errors.add(:base, :active_session_exists)
  end
end
