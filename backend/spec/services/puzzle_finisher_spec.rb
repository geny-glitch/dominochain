# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuzzleFinisher do
  let(:user) { create(:user, :beta) }
  let(:photo) { create(:leverage_photo, :with_images, user: user) }
  let(:session) do
    create(:puzzle_session, :active, user: user, leverage_photo: photo, piece_count: 9, grid_cols: 3, grid_rows: 3, pieces_total: 9)
  end

  before do
    stub_beta_catalog_feature_flags(
      "beta_source_puzzle" => true,
      "beta_action_chaster" => true,
      "beta_action_leverage_photo" => true,
      "beta_action_puzzle" => true
    )
    user.ensure_puzzle_config!
  end

  it "marks completed when all pieces are in place" do
    positions = (0...9).to_a
    result = described_class.new(session: session, outcome: :complete, piece_positions: positions, pieces_placed: 9).call

    expect(result.ok).to eq(true)
    expect(result.kind).to eq("completed")
    expect(session.reload.status).to eq("completed")
    expect(session.puzzle_session_events.last.kind).to eq("completed")
  end

  it "marks completed_in_time when finished before deadline" do
    session.update!(time_limit_seconds: 600, deadline_at: 5.minutes.from_now)
    positions = (0...9).to_a
    result = described_class.new(session: session, outcome: :complete, piece_positions: positions).call

    expect(result.ok).to eq(true)
    expect(result.kind).to eq("completed_in_time")
  end

  it "trusts a completion with no piece grid (free-form puzzle engine)" do
    result = described_class.new(session: session, outcome: :complete, pieces_placed: 9).call

    expect(result.ok).to eq(true)
    expect(result.kind).to eq("completed")
    expect(session.reload.status).to eq("completed")
    expect(session.pieces_placed).to eq(9)
  end

  it "rejects invalid completion grids" do
    result = described_class.new(session: session, outcome: :complete, piece_positions: [1, 0, 2, 3, 4, 5, 6, 7, 8]).call

    expect(result.ok).to eq(false)
    expect(result.error).to eq(:invalid_completion)
    expect(session.reload.status).to eq("active")
  end

  it "records abandoned outcomes" do
    result = described_class.new(session: session, outcome: :abandon, pieces_placed: 3).call

    expect(result.ok).to eq(true)
    expect(result.kind).to eq("abandoned")
    expect(session.reload.status).to eq("abandoned")
  end
end
