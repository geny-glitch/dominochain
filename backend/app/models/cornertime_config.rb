# frozen_string_literal: true

class CornertimeConfig < ApplicationRecord
  SENSITIVITIES = %w[low medium high].freeze

  # Diffy-style presets (see https://github.com/maniart/diffyjs):
  # - diff_sensitivity: contrast amp on consecutive-frame blend (0..1, ~0.2 typical)
  # - pixel_threshold: min abs luma delta (0..255) that paints a motion pixel
  # - motion_threshold: fraction of matrix cells that must be active to count as movement
  DIFFY_PRESETS = {
    "low" => { diff_sensitivity: 0.15, pixel_threshold: 30, motion_threshold: 0.22 }.freeze,
    "medium" => { diff_sensitivity: 0.2, pixel_threshold: 21, motion_threshold: 0.12 }.freeze,
    "high" => { diff_sensitivity: 0.35, pixel_threshold: 15, motion_threshold: 0.06 }.freeze
  }.freeze

  MATRIX_WIDTH = 12
  MATRIX_HEIGHT = 8
  SOURCE_WIDTH = 160
  SOURCE_HEIGHT = 120
  # A matrix cell is "active" when its Diffy average is below this (0 = full motion, 255 = still).
  CELL_ACTIVE_BELOW = 200

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

  def diffy_preset
    DIFFY_PRESETS.fetch(sensitivity, DIFFY_PRESETS["medium"])
  end

  def motion_threshold
    diffy_preset[:motion_threshold]
  end

  def client_config_payload
    preset = diffy_preset
    {
      sensitivity: sensitivity,
      detector: "diffy",
      diff_sensitivity: preset[:diff_sensitivity],
      pixel_threshold: preset[:pixel_threshold],
      motion_threshold: preset[:motion_threshold],
      cell_active_below: CELL_ACTIVE_BELOW,
      matrix_width: MATRIX_WIDTH,
      matrix_height: MATRIX_HEIGHT,
      source_width: SOURCE_WIDTH,
      source_height: SOURCE_HEIGHT,
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
