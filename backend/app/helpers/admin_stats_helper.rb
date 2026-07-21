# frozen_string_literal: true

module AdminStatsHelper
  SOURCE_LABEL_KEYS = {
    "wallpaper" => "beta.scenarios.hub.sources.wallpaper",
    "cornertime" => "beta.scenarios.hub.sources.cornertime",
    "strava" => "beta.scenarios.hub.sources.strava",
    "puryfi" => "beta.catalog.sources.puryfi.label",
    "cigarettes" => "beta.catalog.sources.cigarettes.label",
    "showcase" => "beta.catalog.sources.showcase.label"
  }.freeze

  ACTION_LABEL_KEYS = {
    "chaster.add_time" => "beta.sanctions.chaster.add_time.label",
    "chaster.freeze" => "beta.sanctions.chaster.freeze.label",
    "chaster.unfreeze" => "admin_stats.actions.chaster_unfreeze",
    "pishock.shock" => "beta.sanctions.pishock.shock.label",
    "leverage_photo.lock" => "beta.sanctions.leverage_photo.lock.label",
    "leverage_photo.delete" => "beta.sanctions.leverage_photo.delete.label"
  }.freeze

  def admin_stats_source_label(source)
    t(SOURCE_LABEL_KEYS.fetch(source, "admin_stats.unknown_source"), default: source.humanize)
  end

  def admin_stats_action_label(possibility_id)
    t(ACTION_LABEL_KEYS.fetch(possibility_id, "admin_stats.unknown_action"), default: possibility_id)
  end
end
