# frozen_string_literal: true

class ConsolidateWallpaperEnforcementSanctions < ActiveRecord::Migration[7.2]
  class MigrationConfig < ApplicationRecord
    self.table_name = "wallpaper_enforcement_configs"
  end

  def up
    add_column :wallpaper_enforcement_configs, :permissions_lost_delay_minutes, :integer, null: false, default: 0
    add_column :wallpaper_enforcement_configs, :app_unreachable_delay_minutes, :integer, null: false, default: 0
    add_column :wallpaper_enforcement_configs, :permissions_lost_since, :datetime
    add_column :wallpaper_enforcement_configs, :app_unreachable_since, :datetime

    MigrationConfig.reset_column_information
    MigrationConfig.find_each do |config|
      add_time = config.mismatch_add_time_sanction.is_a?(Hash) ? config.mismatch_add_time_sanction.stringify_keys : {}
      freeze = config.mismatch_freeze_sanction.is_a?(Hash) ? config.mismatch_freeze_sanction.stringify_keys : {}

      config.update_columns(
        mismatch_add_time_sanction: merge_mismatch_sanctions(add_time, freeze),
        permissions_lost_sanction: migrate_sanction(config.permissions_lost_sanction),
        app_unreachable_sanction: migrate_sanction(config.app_unreachable_sanction)
      )
    end

    remove_column :wallpaper_enforcement_configs, :mismatch_freeze_delay_minutes
    remove_column :wallpaper_enforcement_configs, :mismatch_freeze_sanction
    rename_column :wallpaper_enforcement_configs, :mismatch_add_time_delay_minutes, :mismatch_delay_minutes
    rename_column :wallpaper_enforcement_configs, :mismatch_add_time_sanction, :mismatch_sanction
  end

  def down
    rename_column :wallpaper_enforcement_configs, :mismatch_sanction, :mismatch_add_time_sanction
    rename_column :wallpaper_enforcement_configs, :mismatch_delay_minutes, :mismatch_add_time_delay_minutes

    add_column :wallpaper_enforcement_configs, :mismatch_freeze_delay_minutes, :integer, null: false, default: 60
    add_column :wallpaper_enforcement_configs, :mismatch_freeze_sanction, :jsonb, null: false, default: legacy_default_sanction

    MigrationConfig.reset_column_information
    MigrationConfig.find_each do |config|
      modern = config.mismatch_add_time_sanction.is_a?(Hash) ? config.mismatch_add_time_sanction.stringify_keys : {}
      config.update_columns(
        mismatch_add_time_sanction: split_add_time_sanction(modern),
        mismatch_freeze_sanction: split_freeze_sanction(modern),
        permissions_lost_sanction: revert_sanction(config.permissions_lost_sanction),
        app_unreachable_sanction: revert_sanction(config.app_unreachable_sanction)
      )
    end

    remove_column :wallpaper_enforcement_configs, :permissions_lost_delay_minutes
    remove_column :wallpaper_enforcement_configs, :app_unreachable_delay_minutes
    remove_column :wallpaper_enforcement_configs, :permissions_lost_since
    remove_column :wallpaper_enforcement_configs, :app_unreachable_since
  end

  private

  def legacy_default_sanction
    {
      "action" => "none",
      "chaster_seconds" => 3600,
      "pishock_intensity" => 50,
      "pishock_duration" => 1
    }
  end

  def merge_mismatch_sanctions(add_time, freeze)
    {
      "chaster_add_time_enabled" => add_time["action"] == "chaster_add_time",
      "chaster_seconds" => add_time["action"] == "chaster_add_time" ? add_time["chaster_seconds"] : nil,
      "chaster_freeze_enabled" => freeze["action"] == "chaster_freeze",
      "pishock_enabled" => add_time["action"] == "pishock" || freeze["action"] == "pishock",
      "pishock_intensity" => add_time["pishock_intensity"] || freeze["pishock_intensity"] || 50,
      "pishock_duration" => add_time["pishock_duration"] || freeze["pishock_duration"] || 1
    }
  end

  def migrate_sanction(value)
    hash = value.is_a?(Hash) ? value.stringify_keys : {}
    action = hash["action"].to_s
    {
      "chaster_add_time_enabled" => action == "chaster_add_time",
      "chaster_seconds" => action == "chaster_add_time" ? hash["chaster_seconds"] : nil,
      "chaster_freeze_enabled" => action == "chaster_freeze",
      "pishock_enabled" => action == "pishock",
      "pishock_intensity" => hash["pishock_intensity"] || 50,
      "pishock_duration" => hash["pishock_duration"] || 1
    }
  end

  def split_add_time_sanction(modern)
    if modern["chaster_add_time_enabled"] == true
      {
        "action" => "chaster_add_time",
        "chaster_seconds" => modern["chaster_seconds"] || 3600,
        "pishock_intensity" => modern["pishock_intensity"] || 50,
        "pishock_duration" => modern["pishock_duration"] || 1
      }
    elsif modern["pishock_enabled"] == true
      {
        "action" => "pishock",
        "chaster_seconds" => 3600,
        "pishock_intensity" => modern["pishock_intensity"] || 50,
        "pishock_duration" => modern["pishock_duration"] || 1
      }
    else
      legacy_default_sanction
    end
  end

  def split_freeze_sanction(modern)
    if modern["chaster_freeze_enabled"] == true
      {
        "action" => "chaster_freeze",
        "chaster_seconds" => 3600,
        "pishock_intensity" => modern["pishock_intensity"] || 50,
        "pishock_duration" => modern["pishock_duration"] || 1
      }
    else
      legacy_default_sanction
    end
  end

  def revert_sanction(value)
    hash = value.is_a?(Hash) ? value.stringify_keys : {}
    if hash["chaster_add_time_enabled"] == true
      {
        "action" => "chaster_add_time",
        "chaster_seconds" => hash["chaster_seconds"] || 3600,
        "pishock_intensity" => hash["pishock_intensity"] || 50,
        "pishock_duration" => hash["pishock_duration"] || 1
      }
    elsif hash["chaster_freeze_enabled"] == true
      {
        "action" => "chaster_freeze",
        "chaster_seconds" => 3600,
        "pishock_intensity" => hash["pishock_intensity"] || 50,
        "pishock_duration" => hash["pishock_duration"] || 1
      }
    elsif hash["pishock_enabled"] == true
      {
        "action" => "pishock",
        "chaster_seconds" => 3600,
        "pishock_intensity" => hash["pishock_intensity"] || 50,
        "pishock_duration" => hash["pishock_duration"] || 1
      }
    else
      legacy_default_sanction
    end
  end
end
