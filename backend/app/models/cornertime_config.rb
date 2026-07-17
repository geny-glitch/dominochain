# frozen_string_literal: true

class CornertimeConfig < ApplicationRecord
  SENSITIVITIES = %w[low medium high].freeze
  # Fraction of pixels that must change vs calibration baseline (0..1).
  # Local body motion only affects part of the frame, so mean-abs thresholds
  # were far too high and missed obvious movement.
  MOTION_THRESHOLDS = {
    "low" => 0.08,
    "medium" => 0.04,
    "high" => 0.02
  }.freeze
  # Per-pixel luma delta (0..1) required to count a pixel as "changed".
  PIXEL_CHANGE_DELTA = 0.10

  MIN_COOLDOWN_SECONDS = 5
  MAX_COOLDOWN_SECONDS = 600
  MIN_CALIBRATION_SECONDS = 2
  MAX_CALIBRATION_SECONDS = 30

  belongs_to :user

  validates :sensitivity, inclusion: { in: SENSITIVITIES }
  validates :violation_cooldown_seconds,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_COOLDOWN_SECONDS,
      less_than_or_equal_to: MAX_COOLDOWN_SECONDS
    }
  validates :calibration_seconds,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_CALIBRATION_SECONDS,
      less_than_or_equal_to: MAX_CALIBRATION_SECONDS
    }
  validate :movement_sanction_is_valid

  def movement_sanction_object
    SanctionSet.from_hash(
      movement_sanction,
      allowed: BetaEvents::SourceRegistry.allowed_for(:cornertime, :movement_detected)
    )
  end

  def motion_threshold
    MOTION_THRESHOLDS.fetch(sensitivity, MOTION_THRESHOLDS["medium"])
  end

  def client_config_payload
    {
      sensitivity: sensitivity,
      motion_threshold: motion_threshold,
      pixel_change_delta: PIXEL_CHANGE_DELTA,
      violation_cooldown_seconds: violation_cooldown_seconds,
      calibration_seconds: calibration_seconds
    }
  end

  private

  def movement_sanction_is_valid
    sanction = movement_sanction_object
    if sanction.enabled?("chaster.add_time") && !sanction.item_for("chaster.add_time")&.active?
      errors.add(:movement_sanction, :invalid)
    end
    if sanction.enabled?("leverage_photo.lock") && !sanction.item_for("leverage_photo.lock")&.active?
      errors.add(:movement_sanction, :invalid)
    end
  end
end
