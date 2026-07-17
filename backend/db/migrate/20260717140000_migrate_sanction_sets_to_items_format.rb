# frozen_string_literal: true

class MigrateSanctionSetsToItemsFormat < ActiveRecord::Migration[7.2]
  def up
    migrate_wallpaper_configs!
    migrate_strava_goals!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def migrate_wallpaper_configs!
    say_with_time "wallpaper_enforcement_configs sanctions → items[]" do
      WallpaperEnforcementConfig.reset_column_information
      WallpaperEnforcementConfig.find_each do |config|
        updates = {}
        %i[mismatch_sanction permissions_lost_sanction app_unreachable_sanction].each do |attr|
          raw = config.public_send(attr)
          next if raw.blank?
          next if raw.is_a?(Hash) && raw.key?("items")

          updates[attr] = SanctionSet.from_hash(raw, allowed: BetaEvents::SourceRegistry::WALLPAPER_ALLOWED).to_h
        end
        config.update_columns(updates) if updates.any?
      end
    end
  end

  def migrate_strava_goals!
    say_with_time "strava_goals.failure_sanction → items[]" do
      StravaGoal.reset_column_information
      StravaGoal.find_each do |goal|
        raw = goal.failure_sanction
        next if raw.blank?
        next if raw.is_a?(Hash) && raw.key?("items")

        converted = SanctionSet.from_hash(raw, allowed: BetaEvents::SourceRegistry::STRAVA_ALLOWED).to_h
        goal.update_columns(failure_sanction: converted)
      end
    end
  end
end
