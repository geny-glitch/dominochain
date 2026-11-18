# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperRotations::Schedule do
  let(:anchor) { Time.zone.parse("2026-11-18 12:00:00") }
  let(:interval) { 30 }

  def slot_at(seconds)
    described_class.slot_index(anchor_at: anchor, interval_seconds: interval, at: anchor + seconds)
  end

  it "counts whole intervals from the anchor" do
    expect(slot_at(0)).to eq(0)
    expect(slot_at(29)).to eq(0)
    expect(slot_at(30)).to eq(1)
    expect(slot_at(120)).to eq(4)
  end

  it "does not go negative before the anchor" do
    expect(slot_at(-10)).to eq(0)
  end

  it "builds a collage about one slot in five" do
    expect(described_class.collage?(slot: 0, count: 3, collages_enabled: true)).to eq(false)
    expect(described_class.collage?(slot: 4, count: 3, collages_enabled: true)).to eq(true)
    expect(described_class.collage?(slot: 9, count: 3, collages_enabled: true)).to eq(true)
    expect(described_class.collage?(slot: 4, count: 3, collages_enabled: false)).to eq(false)
    expect(described_class.collage?(slot: 4, count: 1, collages_enabled: true)).to eq(false)
  end

  it "picks one photo, or 2, or 4 walking forward from the slot" do
    expect(described_class.indexes(slot: 5, count: 3, collage: false)).to eq([2])
    expect(described_class.indexes(slot: 4, count: 3, collage: true)).to eq([1, 2])
    expect(described_class.indexes(slot: 4, count: 4, collage: true)).to eq([0, 1, 2, 3])
    expect(described_class.indexes(slot: 9, count: 4, collage: true)).to eq([1, 2])
  end
end
