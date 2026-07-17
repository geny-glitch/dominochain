# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::ConsequenceResolver do
  let(:beta) { build_stubbed(:user) }

  it "resolves fixed cigarette pipeline to chaster.add_time" do
    event = BetaEvents::DomainEvent.new(
      beta: beta,
      source: :cigarette,
      kind: :smoked_add_time,
      payload: { seconds: 120 }
    )

    resolved = described_class.resolved_actions_for(event)
    expect(resolved.size).to eq(1)
    expect(resolved.first.executor).to eq(BetaEvents::Actions::ChasterAddTimeFromEvent)
    expect(resolved.first.config[:seconds]).to eq(120)
  end

  it "resolves wallpaper payload by possibility_id" do
    event = BetaEvents::DomainEvent.new(
      beta: beta,
      source: :wallpaper,
      kind: :mismatch_add_time,
      payload: { possibility_id: "chaster.add_time", seconds: 60 }
    )

    resolved = described_class.resolved_actions_for(event)
    expect(resolved.map(&:possibility_id)).to eq([ "chaster.add_time" ])
  end

  it "resolves legacy action string on wallpaper" do
    event = BetaEvents::DomainEvent.new(
      beta: beta,
      source: :wallpaper,
      kind: :mismatch_pishock,
      payload: { action: "pishock", pishock_intensity: 20, pishock_duration: 2 }
    )

    resolved = described_class.resolved_actions_for(event)
    expect(resolved.first.possibility_id).to eq("pishock.shock")
    expect(resolved.first.executor).to eq(BetaEvents::Actions::EnqueuePishockFromEvent)
  end

  it "resolves showcase snake to pishock then chaster with rate_limit" do
    event = BetaEvents::DomainEvent.new(
      beta: beta,
      source: :showcase_game,
      kind: :score_time_applied,
      payload: { seconds: 300, game_kind: "snake" }
    )

    resolved = described_class.resolved_actions_for(event)
    expect(resolved.map(&:possibility_id)).to eq(%w[pishock.shock chaster.add_time])
    expect(resolved.first.config).to eq(intensity: 1, duration: 1)
    expect(resolved.last.config[:seconds]).to eq(300)
    expect(resolved.last.config[:rate_limit]).to be_present
  end

  it "skips pishock for quiz showcase scores" do
    event = BetaEvents::DomainEvent.new(
      beta: beta,
      source: :showcase_game,
      kind: :score_time_applied,
      payload: { seconds: 10, game_kind: "quiz" }
    )

    resolved = described_class.resolved_actions_for(event)
    expect(resolved.map(&:possibility_id)).to eq(%w[chaster.add_time])
  end
end
