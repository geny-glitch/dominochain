# frozen_string_literal: true

class ZapProgram < ApplicationRecord
  SOURCES = %w[boss public].freeze
  MAX_SLOTS = 12

  belongs_to :beta, class_name: "User"
  belongs_to :boss, class_name: "User", optional: true
  has_many :zap_slots, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :zap_program

  validates :source, inclusion: { in: SOURCES }
  validates :beta_id, uniqueness: { scope: :source }
  validates :generation, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :boss_required_for_boss_source
  validate :boss_absent_for_public_source

  scope :armed, -> { where(armed: true) }

  class << self
    def find_or_create_for!(beta:, source:, boss: nil)
      source = source.to_s
      program = find_or_initialize_by(beta_id: beta.id, source: source)
      if program.new_record?
        program.boss = (source == "boss") ? boss : nil
        program.save!
      elsif source == "boss" && boss.present? && program.boss_id != boss.id
        program.update!(boss: boss)
      end
      program
    end

    def disarm_boss_for_beta!(beta)
      where(beta_id: beta.id, source: "boss").find_each(&:disarm!)
    end

    def disarm_public_for_beta!(beta)
      where(beta_id: beta.id, source: "public").find_each(&:disarm!)
    end

    def disarm_all_for_beta!(beta)
      where(beta_id: beta.id).find_each(&:disarm!)
    end
  end

  def arm!
    update!(armed: true)
  end

  def disarm!
    with_lock do
      update!(armed: false, generation: generation + 1, busy_until: nil)
    end
  end

  def busy?(at: Time.current)
    busy_until.present? && busy_until > at
  end

  def claim_busy!(seconds, at: Time.current)
    with_lock do
      reload
      return false if busy?(at: at)

      update!(busy_until: at + seconds.to_i.seconds)
      true
    end
  end

  def slots_full?
    zap_slots.count >= MAX_SLOTS
  end

  def analytics_source
    source == "boss" ? "zap_program_boss" : "zap_program_public"
  end

  def can_run_scheduled?
    armed? && delivery_allowed?
  end

  def can_run_manual?
    delivery_allowed?
  end

  def delivery_allowed?
    return false unless beta.pishock_enabled?
    return false unless BetaCatalog.new(beta).action_enabled?("pishock")

    case source
    when "boss"
      boss_id.present? && Control.exists?(boss_id: boss_id, beta_id: beta_id, status: :accepted)
    when "public"
      beta.public_pishock_enabled?
    else
      false
    end
  end

  def generation_matches?(expected)
    generation == expected.to_i
  end

  private

  def boss_required_for_boss_source
    return unless source == "boss"
    return if boss_id.present?

    errors.add(:boss, :blank)
  end

  def boss_absent_for_public_source
    return unless source == "public"
    return if boss_id.blank?

    errors.add(:boss, :present)
  end
end
