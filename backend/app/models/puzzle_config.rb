# frozen_string_literal: true

class PuzzleConfig < ApplicationRecord
  REFERENCE_MODES = %w[original blurred none].freeze
  MIN_PIECE_COUNT = 4
  MAX_PIECE_COUNT = 120
  DEFAULT_PIECE_COUNT = 25
  # Legacy perfect-square presets (kept for older UI copy / migration references).
  ALLOWED_PIECE_COUNTS = [9, 16, 25, 36, 49, 64, 81].freeze
  MIN_COOLDOWN_SECONDS = 0
  MAX_COOLDOWN_SECONDS = 86_400
  MIN_TIME_LIMIT_SECONDS = 60
  MAX_TIME_LIMIT_SECONDS = 86_400

  belongs_to :user

  validates :default_piece_count,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_PIECE_COUNT,
      less_than_or_equal_to: MAX_PIECE_COUNT
    }
  validates :default_reference_mode, inclusion: { in: REFERENCE_MODES }
  validates :cooldown_seconds,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_COOLDOWN_SECONDS,
      less_than_or_equal_to: MAX_COOLDOWN_SECONDS
    }
  validates :default_time_limit_seconds,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: MIN_TIME_LIMIT_SECONDS,
      less_than_or_equal_to: MAX_TIME_LIMIT_SECONDS
    },
    allow_nil: true
  validate :scenarios_are_valid

  def reload(*)
    @scenario_set = nil
    super
  end

  def scenario_set
    @scenario_set ||= ScenarioSet.from_hash(self[:scenarios], source: :puzzle)
  end

  def scenario_for(event)
    scenario_set.for_event(event)
  end

  def assign_scenarios!(scenario_set)
    self.scenarios = scenario_set.to_h
    @scenario_set = scenario_set
  end

  def self.kind_map_for(event_kind)
    kind = event_kind.to_sym
    {
      "chaster.add_time" => kind,
      "chaster.freeze" => kind,
      "pishock.shock" => kind,
      "leverage_photo.lock" => kind,
      "leverage_photo.delete" => kind,
      "leverage_photo.crop_to_progress" => kind,
      "puzzle.assign" => kind
    }
  end

  def self.grid_for_piece_count(piece_count)
    count = [piece_count.to_i, MIN_PIECE_COUNT].max

    best_cols = Math.sqrt(count).ceil
    best_rows = (count.to_f / best_cols).ceil
    best_score = (best_cols - best_rows).abs * 10 + (best_cols * best_rows - count)

    max_side = Math.sqrt(count).ceil + 3
    (1..max_side).each do |cols|
      rows = (count.to_f / cols).ceil
      next if rows < 1

      score = (cols - rows).abs * 10 + (cols * rows - count)
      next if score >= best_score

      best_score = score
      best_cols = cols
      best_rows = rows
    end

    [best_cols, best_rows]
  end

  def self.clamp_piece_count(raw, fallback: DEFAULT_PIECE_COUNT)
    count = raw.to_i
    return fallback if count <= 0

    count.clamp(MIN_PIECE_COUNT, MAX_PIECE_COUNT)
  end

  private

  def scenarios_are_valid
    scenario_set.scenarios.each do |scenario|
      allowed = BetaEvents::SourceRegistry.allowed_for(:puzzle, scenario.event)
      sanction = scenario.to_sanction_set(allowed: allowed)
      if sanction.enabled?("chaster.add_time") && !sanction.item_for("chaster.add_time")&.active?
        errors.add(:scenarios, :invalid)
      end
      if sanction.enabled?("leverage_photo.lock") && !sanction.item_for("leverage_photo.lock")&.active?
        errors.add(:scenarios, :invalid)
      end
      if sanction.enabled?("puzzle.assign") && !sanction.item_for("puzzle.assign")&.active?
        errors.add(:scenarios, :invalid)
      end
    end
  end
end
