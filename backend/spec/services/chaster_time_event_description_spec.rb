# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChasterTimeEventDescription do
  describe ".enrich_add_time" do
    it "builds a snake game summary and metadata" do
      result = described_class.enrich_add_time(
        event_source: :showcase_game,
        event_kind: :score_time_applied,
        payload: { seconds: 300, game_kind: "snake" }
      )

      expect(result[:metadata]).to include("game_kind" => "snake")
      expect(result[:summary]).to eq(I18n.t("chaster.time_events.summaries.showcase_game", game: "Snake"))
    end

    it "builds a backdoor summary with player name and message" do
      result = described_class.enrich_add_time(
        event_source: :showcase_backdoor,
        event_kind: :time_committed,
        payload: { seconds: 120, player_name: "Visitor", message: "Hello beta" }
      )

      expect(result[:metadata]).to include("player_name" => "Visitor", "message" => "Hello beta")
      expect(result[:summary]).to include("Visitor")
      expect(result[:summary]).to include("Hello beta")
    end

    it "builds a wallpaper mismatch summary" do
      result = described_class.enrich_add_time(
        event_source: :wallpaper,
        event_kind: :mismatch_add_time,
        payload: { seconds: 600, action: "chaster_add_time", enforcement_kind: "mismatch_add_time" }
      )

      expect(result[:metadata]).to include("enforcement_kind" => "mismatch_add_time")
      expect(result[:summary]).to eq(I18n.t("chaster.time_events.summaries.wallpaper.mismatch_add_time"))
    end
  end

  describe ".for_event" do
    it "returns a snake-specific source label from metadata" do
      event = build(
        :chaster_time_event,
        source: "showcase_game",
        metadata: { "game_kind" => "snake" },
        summary: "Snake"
      )

      description = described_class.for_event(event)

      expect(description[:source_label]).to eq(I18n.t("chaster.time_events.sources.showcase_game_snake"))
      expect(description[:summary]).to eq(I18n.t("chaster.time_events.summaries.showcase_game", game: "Snake"))
    end
  end
end
