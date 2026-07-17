# frozen_string_literal: true

class CornertimeConfig < ApplicationRecord
  SENSITIVITIES = %w[low medium high].freeze

  # Dual detector:
  # 1) Diffy consecutive-frame (instant motion)
  # 2) Pose drift vs calibration baseline (slow crawl / leaving the frame)
  #    — must stay above drift_threshold for drift_hold_ms (tolerates rebalancing)
  DETECTOR_PRESETS = {
    "low" => {
      diff_sensitivity: 0.15,
      pixel_threshold: 30,
      motion_threshold: 0.22,
      drift_threshold: 0.28,
      drift_hold_ms: 2500,
      drift_pixel_delta: 22
    }.freeze,
    "medium" => {
      diff_sensitivity: 0.2,
      pixel_threshold: 21,
      motion_threshold: 0.12,
      drift_threshold: 0.18,
      drift_hold_ms: 1800,
      drift_pixel_delta: 18
    }.freeze,
    "high" => {
      diff_sensitivity: 0.35,
      pixel_threshold: 15,
      motion_threshold: 0.06,
      drift_threshold: 0.12,
      drift_hold_ms: 1200,
      drift_pixel_delta: 14
    }.freeze
  }.freeze

  MATRIX_WIDTH = 12
  MATRIX_HEIGHT = 8
  SOURCE_WIDTH = 160
  SOURCE_HEIGHT = 120
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
  validate :scenarios_are_valid

  def reload(*)
    @scenario_set = nil
    @stored_scenario_set = nil
    super
  end

  def scenario_set
    @scenario_set ||= begin
      stored = stored_scenario_set
      stored.any? ? stored : ScenarioSet.from_legacy_cornertime(self)
    end
  end

  def scenario_for(event)
    scenario_set.for_event(event)
  end

  # Compat readers: stored scenarios win; empty → legacy sanction JSONB.
  def movement_sanction_object
    if stored_scenario_set.any?
      scenario_for("movement_detected")&.to_sanction_set ||
        SanctionSet.from_hash({}, allowed: movement_allowed)
    else
      SanctionSet.from_hash(movement_sanction, allowed: movement_allowed)
    end
  end

  def early_stop_sanction_object
    if stored_scenario_set.any?
      scenario_for("early_stop")&.to_sanction_set ||
        SanctionSet.from_hash({}, allowed: early_stop_allowed)
    else
      SanctionSet.from_hash(early_stop_sanction, allowed: early_stop_allowed)
    end
  end

  def assign_scenarios!(scenario_set)
    self.scenarios = scenario_set.to_h
    blank = { "items" => [] }
    self.movement_sanction = blank
    self.early_stop_sanction = blank
    @scenario_set = scenario_set
    @stored_scenario_set = scenario_set
  end

  def detector_preset
    DETECTOR_PRESETS.fetch(sensitivity, DETECTOR_PRESETS["medium"])
  end

  def motion_threshold
    detector_preset[:motion_threshold]
  end

  def client_config_payload
    preset = detector_preset
    {
      sensitivity: sensitivity,
      detector: "diffy_plus_drift",
      diff_sensitivity: preset[:diff_sensitivity],
      pixel_threshold: preset[:pixel_threshold],
      motion_threshold: preset[:motion_threshold],
      drift_threshold: preset[:drift_threshold],
      drift_hold_ms: preset[:drift_hold_ms],
      drift_pixel_delta: preset[:drift_pixel_delta],
      cell_active_below: CELL_ACTIVE_BELOW,
      matrix_width: MATRIX_WIDTH,
      matrix_height: MATRIX_HEIGHT,
      source_width: SOURCE_WIDTH,
      source_height: SOURCE_HEIGHT,
      violation_cooldown_seconds: violation_cooldown_seconds,
      calibration_seconds: calibration_seconds,
      allowed_durations_minutes: CornertimeSession::ALLOWED_DURATIONS_MINUTES
    }
  end

  def self.kind_map_for(event_kind)
    kind = event_kind.to_sym
    {
      "chaster.add_time" => kind,
      "chaster.freeze" => kind,
      "pishock.shock" => kind,
      "leverage_photo.lock" => kind,
      "leverage_photo.delete" => kind
    }
  end

  private

  def movement_allowed
    BetaEvents::SourceRegistry.allowed_for(:cornertime, :movement_detected)
  end

  def early_stop_allowed
    BetaEvents::SourceRegistry.allowed_for(:cornertime, :early_stop)
  end

  def stored_scenario_set
    @stored_scenario_set ||= ScenarioSet.from_hash(self[:scenarios], source: :cornertime)
  end

  def scenarios_are_valid
    scenario_set.scenarios.each do |scenario|
      allowed = case scenario.event
      when "early_stop" then early_stop_allowed
      else movement_allowed
      end
      sanction = scenario.to_sanction_set(allowed: allowed)
      if sanction.enabled?("chaster.add_time") && !sanction.item_for("chaster.add_time")&.active?
        errors.add(:scenarios, :invalid)
      end
      if sanction.enabled?("leverage_photo.lock") && !sanction.item_for("leverage_photo.lock")&.active?
        errors.add(:scenarios, :invalid)
      end
    end
  end
end
