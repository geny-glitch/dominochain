# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::SanctionApplier do
  let(:beta) { create(:user, :beta) }

  it "applies each active item as a separate event" do
    sanction = SanctionSet.from_hash(
      {
        "items" => [
          { "possibility_id" => "chaster.add_time", "enabled" => true, "config" => { "seconds" => 90 } },
          { "possibility_id" => "pishock.shock", "enabled" => true, "config" => { "intensity" => 10, "duration" => 1 } }
        ]
      },
      allowed: %w[chaster.add_time pishock.shock]
    )

    events = []
    applier = described_class.new(
      beta: beta,
      source: :wallpaper,
      kind_map: {
        "chaster.add_time" => :mismatch_add_time,
        "pishock.shock" => :mismatch_pishock
      },
      execute: lambda { |event, _context|
        events << event
        :ok
      }
    )

    results = applier.apply!(sanction)
    expect(results.size).to eq(2)
    expect(events.map(&:kind)).to eq(%i[mismatch_add_time mismatch_pishock])
    expect(events.map { |e| e[:possibility_id] }).to eq(%w[chaster.add_time pishock.shock])
    expect(events.first[:seconds]).to eq(90)
  end

  it "multiplies chaster seconds when override is set" do
    sanction = SanctionSet.from_hash(
      {
        "items" => [
          { "possibility_id" => "chaster.add_time", "enabled" => true, "config" => { "seconds" => 10 } }
        ]
      },
      allowed: %w[chaster.add_time]
    )

    captured = nil
    applier = described_class.new(
      beta: beta,
      source: :wallpaper,
      kind_map: { "chaster.add_time" => :mismatch_add_time },
      execute: lambda { |event, _context|
        captured = event
        :ok
      }
    )

    applier.apply!(sanction, config_overrides: { "chaster.add_time" => { seconds_multiplier: 3 } })
    expect(captured[:seconds]).to eq(30)
  end
end
