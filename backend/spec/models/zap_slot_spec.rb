# frozen_string_literal: true

require "rails_helper"

RSpec.describe ZapSlot, type: :model do
  let(:beta) { create(:user, :beta, time_zone: "Europe/Paris") }
  let(:program) { create(:zap_program, beta: beta) }

  describe "validations" do
    it "accepts a daily single slot" do
      slot = build(:zap_slot, zap_program: program)
      expect(slot).to be_valid
    end

    it "rejects more than 12 slots on a program" do
      ZapProgram::MAX_SLOTS.times do |i|
        create(:zap_slot, zap_program: program, position: i, time_of_day_minutes: i)
      end
      extra = build(:zap_slot, zap_program: program, position: 99, time_of_day_minutes: 100)
      expect(extra).not_to be_valid
      expect(extra.errors[:base]).to be_present
    end

    it "rejects roulette when min > max" do
      slot = build(:zap_slot, :roulette, zap_program: program, intensity_min: 80, intensity_max: 10)
      expect(slot).not_to be_valid
    end
  end

  describe "#due?" do
    it "is due for daily at the matching local minute once per day" do
      slot = create(:zap_slot, zap_program: program, time_of_day_minutes: 8 * 60)
      at = Time.find_zone("Europe/Paris").local(2026, 11, 12, 8, 0, 10)
      expect(slot.due?(at: at)).to be true

      slot.mark_fired!(at: at)
      expect(slot.due?(at: at)).to be false
      expect(slot.due?(at: at + 1.day)).to be true
    end

    it "does not catch up a missed daily minute" do
      slot = create(:zap_slot, zap_program: program, time_of_day_minutes: 8 * 60)
      at = Time.find_zone("Europe/Paris").local(2026, 11, 12, 8, 1, 0)
      expect(slot.due?(at: at)).to be false
    end

    it "is due once at the exact local minute" do
      fires_at = Time.find_zone("Europe/Paris").local(2026, 11, 13, 21, 0, 0)
      slot = create(:zap_slot, :once, zap_program: program, fires_at: fires_at)
      expect(slot.due?(at: fires_at + 10.seconds)).to be true
      slot.mark_fired!(at: fires_at)
      expect(slot.once_done?).to be true
      expect(slot.due?(at: fires_at + 1.day)).to be false
    end

    it "respects overnight interval windows" do
      slot = create(
        :zap_slot,
        :interval,
        zap_program: program,
        interval_minutes: 30,
        window_start_minutes: 22 * 60,
        window_end_minutes: 6 * 60
      )
      evening = Time.find_zone("Europe/Paris").local(2026, 11, 12, 23, 0, 0)
      midday = Time.find_zone("Europe/Paris").local(2026, 11, 12, 12, 0, 0)
      expect(slot.due?(at: evening)).to be true
      expect(slot.due?(at: midday)).to be false
    end

    it "waits for the interval before firing again" do
      slot = create(:zap_slot, :interval, zap_program: program, interval_minutes: 45, window_start_minutes: nil, window_end_minutes: nil)
      first = Time.find_zone("Europe/Paris").local(2026, 11, 12, 12, 0, 0)
      expect(slot.due?(at: first)).to be true
      slot.mark_fired!(at: first)
      expect(slot.due?(at: first + 44.minutes)).to be false
      expect(slot.due?(at: first + 45.minutes)).to be true
    end
  end

  describe "#build_shocks" do
    it "builds a single shock" do
      slot = build(:zap_slot, zap_program: program, intensity: 40, duration: 2)
      expect(slot.build_shocks).to eq([ { intensity: 40, duration: 2, delay_seconds: 0 } ])
    end

    it "builds a burst with fixed gap" do
      slot = build(:zap_slot, :burst, zap_program: program, count: 3, intensity: 50, gap_seconds: 2, duration: 1)
      shocks = slot.build_shocks
      expect(shocks.size).to eq(3)
      expect(shocks.map { |s| s[:delay_seconds] }).to eq([ 0, 2, 2 ])
      expect(shocks.map { |s| s[:intensity] }.uniq).to eq([ 50 ])
    end

    it "builds a roulette with random intensities" do
      slot = build(:zap_slot, :roulette, zap_program: program, count: 3, intensity_min: 10, intensity_max: 20, duration: 1)
      shocks = slot.build_shocks
      expect(shocks.size).to eq(3)
      expect(shocks.map { |s| s[:intensity] }).to all(be_between(10, 20))
    end
  end
end
