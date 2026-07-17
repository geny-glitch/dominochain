# frozen_string_literal: true

# Generic multi-action sanction configuration stored as JSONB.
# New format:
#   { "items" => [ { "possibility_id" => "chaster.add_time", "enabled" => true, "config" => { "seconds" => 3600 } } ] }
# Legacy WallpaperSanction flat / single-action formats are accepted via from_hash.
class SanctionSet
  Item = Struct.new(:possibility_id, :enabled, :config, keyword_init: true) do
    def active?
      enabled && config_valid_for_active?
    end

    def config_valid_for_active?
      possibility = BetaEvents::ActionRegistry.find(possibility_id)
      return false unless possibility

      possibility.config_fields.each do |key, schema|
        next unless schema[:required]

        value = config[key.to_sym] || config[key.to_s]
        return false if value.blank? || (value.respond_to?(:to_i) && schema[:type] == :integer && !value.to_i.positive? && schema[:min].to_i.positive?)
      end
      true
    end
  end

  attr_reader :items

  def self.from_hash(value, allowed: nil)
    hash = value.is_a?(Hash) ? value.deep_stringify_keys : {}
    if hash.key?("items")
      from_items_hash(hash, allowed: allowed)
    elsif hash.key?("action")
      from_legacy_single_action(hash, allowed: allowed)
    elsif flat_legacy?(hash)
      from_flat_legacy(hash, allowed: allowed)
    elsif keyed_by_possibility?(hash)
      from_keyed_hash(hash, allowed: allowed)
    else
      new(items: [], allowed: allowed)
    end
  end

  def self.from_params(raw, allowed:)
    return new(items: empty_items_for(allowed), allowed: allowed) if raw.blank?

    hash = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    hash = hash.deep_stringify_keys

    if hash.key?("items")
      from_items_hash(hash, allowed: allowed)
    else
      from_keyed_hash(hash, allowed: allowed)
    end
  end

  def self.empty_items_for(allowed)
    Array(allowed).map do |pid|
      Item.new(possibility_id: pid.to_s, enabled: false, config: {})
    end
  end

  def self.flat_legacy?(hash)
    hash.key?("chaster_add_time_enabled") ||
      hash.key?("chaster_freeze_enabled") ||
      hash.key?("pishock_enabled") ||
      hash.key?("leverage_photo_lock_enabled") ||
      hash.key?("leverage_photo_delete_enabled") ||
      hash.key?("leverage_photo_start_enabled") ||
      hash.key?("leverage_photo_add_time_enabled")
  end

  def self.keyed_by_possibility?(hash)
    hash.keys.any? { |k| BetaEvents::ActionRegistry.find(k) }
  end

  def self.from_items_hash(hash, allowed:)
    raw_items = Array(hash["items"])
    items_by_id = {}

    raw_items.each do |raw|
      next unless raw.is_a?(Hash)

      pid = raw["possibility_id"].to_s
      next if pid.blank?
      next if allowed && !allowed.include?(pid)

      items_by_id[pid] = Item.new(
        possibility_id: pid,
        enabled: ActiveModel::Type::Boolean.new.cast(raw["enabled"]),
        config: BetaEvents::ActionRegistry.normalize_config(pid, raw["config"] || {})
      )
    end

    items = merge_with_allowed(items_by_id, allowed)
    new(items: items, allowed: allowed)
  end

  def self.from_keyed_hash(hash, allowed:)
    items_by_id = {}
    hash.each do |pid, raw|
      next unless BetaEvents::ActionRegistry.find(pid)
      next if allowed && !allowed.include?(pid)
      next unless raw.is_a?(Hash)

      enabled = ActiveModel::Type::Boolean.new.cast(raw["enabled"])
      config_raw = raw["config"].is_a?(Hash) ? raw["config"] : raw.except("enabled", "possibility_id")
      items_by_id[pid] = Item.new(
        possibility_id: pid,
        enabled: enabled,
        config: BetaEvents::ActionRegistry.normalize_config(pid, config_raw)
      )
    end

    items = merge_with_allowed(items_by_id, allowed)
    new(items: items, allowed: allowed)
  end

  def self.from_legacy_single_action(hash, allowed:)
    action = hash["action"].to_s
    pid = BetaEvents::ActionRegistry.possibility_id_for_legacy_action(action)
    items_by_id = {}

    if pid.present?
      config = case pid
      when "chaster.add_time"
        { seconds: hash["chaster_seconds"] }
      when "pishock.shock"
        { intensity: hash["pishock_intensity"], duration: hash["pishock_duration"] }
      else
        {}
      end
      items_by_id[pid] = Item.new(
        possibility_id: pid,
        enabled: true,
        config: BetaEvents::ActionRegistry.normalize_config(pid, config)
      )
    end

    new(items: merge_with_allowed(items_by_id, allowed), allowed: allowed)
  end

  def self.from_flat_legacy(hash, allowed:)
    items_by_id = {}

    if ActiveModel::Type::Boolean.new.cast(hash["chaster_add_time_enabled"])
      items_by_id["chaster.add_time"] = Item.new(
        possibility_id: "chaster.add_time",
        enabled: true,
        config: BetaEvents::ActionRegistry.normalize_config("chaster.add_time", seconds: hash["chaster_seconds"])
      )
    end

    if ActiveModel::Type::Boolean.new.cast(hash["chaster_freeze_enabled"])
      items_by_id["chaster.freeze"] = Item.new(
        possibility_id: "chaster.freeze",
        enabled: true,
        config: {}
      )
    end

    if ActiveModel::Type::Boolean.new.cast(hash["pishock_enabled"])
      items_by_id["pishock.shock"] = Item.new(
        possibility_id: "pishock.shock",
        enabled: true,
        config: BetaEvents::ActionRegistry.normalize_config(
          "pishock.shock",
          intensity: hash["pishock_intensity"],
          duration: hash["pishock_duration"]
        )
      )
    end

    lock = coalesce_lock_fields(hash)
    if lock[:enabled]
      items_by_id["leverage_photo.lock"] = Item.new(
        possibility_id: "leverage_photo.lock",
        enabled: true,
        config: BetaEvents::ActionRegistry.normalize_config(
          "leverage_photo.lock",
          seconds: lock[:seconds],
          target_mode: lock[:target_mode],
          photo_id: lock[:photo_id]
        )
      )
    end

    if ActiveModel::Type::Boolean.new.cast(hash["leverage_photo_delete_enabled"])
      items_by_id["leverage_photo.delete"] = Item.new(
        possibility_id: "leverage_photo.delete",
        enabled: true,
        config: BetaEvents::ActionRegistry.normalize_config(
          "leverage_photo.delete",
          target_mode: hash["leverage_photo_delete_target_mode"],
          photo_id: hash["leverage_photo_delete_photo_id"]
        )
      )
    end

    new(items: merge_with_allowed(items_by_id, allowed), allowed: allowed)
  end

  def self.coalesce_lock_fields(hash)
    if hash.key?("leverage_photo_lock_enabled") || hash.key?("leverage_photo_lock_seconds")
      return {
        enabled: ActiveModel::Type::Boolean.new.cast(hash["leverage_photo_lock_enabled"]),
        seconds: hash["leverage_photo_lock_seconds"],
        target_mode: hash["leverage_photo_lock_target_mode"],
        photo_id: hash["leverage_photo_lock_photo_id"]
      }
    end

    start_enabled = ActiveModel::Type::Boolean.new.cast(hash["leverage_photo_start_enabled"])
    add_enabled = ActiveModel::Type::Boolean.new.cast(hash["leverage_photo_add_time_enabled"])
    if start_enabled
      {
        enabled: true,
        seconds: hash["leverage_photo_start_seconds"],
        target_mode: hash["leverage_photo_start_target_mode"],
        photo_id: hash["leverage_photo_start_photo_id"]
      }
    elsif add_enabled
      {
        enabled: true,
        seconds: hash["leverage_photo_add_time_seconds"],
        target_mode: hash["leverage_photo_add_time_target_mode"],
        photo_id: hash["leverage_photo_add_time_photo_id"]
      }
    else
      { enabled: false, seconds: nil, target_mode: "random", photo_id: nil }
    end
  end

  def self.merge_with_allowed(items_by_id, allowed)
    if allowed.present?
      allowed.map do |pid|
        items_by_id[pid] || Item.new(possibility_id: pid, enabled: false, config: {})
      end
    else
      items_by_id.values
    end
  end

  def initialize(items:, allowed: nil)
    @items = items
    @allowed = allowed
  end

  def item_for(possibility_id)
    items.find { |i| i.possibility_id == possibility_id.to_s }
  end

  def enabled?(possibility_id)
    item_for(possibility_id)&.enabled || false
  end

  def active_items
    items.select(&:active?)
  end

  def any_active?
    active_items.any?
  end

  def active?
    any_active?
  end

  # Legacy bridge for audit history strings.
  def action
    first = active_items.first
    return "none" unless first

    BetaEvents::ActionRegistry.legacy_action_for(first.possibility_id) || first.possibility_id
  end

  def to_h
    {
      "items" => items.map do |item|
        cfg = item.config.deep_stringify_keys
        # Drop nil photo_id when random
        if cfg["target_mode"] == "random"
          cfg = cfg.except("photo_id")
        end
        {
          "possibility_id" => item.possibility_id,
          "enabled" => item.enabled,
          "config" => cfg
        }
      end
    }
  end

  # Convenience readers used by views during migration.
  def chaster_add_time_enabled
    enabled?("chaster.add_time")
  end

  def chaster_seconds
    item_for("chaster.add_time")&.config&.dig(:seconds)
  end

  def chaster_freeze_enabled
    enabled?("chaster.freeze")
  end

  def pishock_enabled
    enabled?("pishock.shock")
  end

  def pishock_intensity
    item_for("pishock.shock")&.config&.dig(:intensity) || 50
  end

  def pishock_duration
    item_for("pishock.shock")&.config&.dig(:duration) || 1
  end

  def leverage_photo_lock_enabled
    enabled?("leverage_photo.lock")
  end

  def leverage_photo_lock_seconds
    item_for("leverage_photo.lock")&.config&.dig(:seconds)
  end

  def leverage_photo_lock_target_mode
    item_for("leverage_photo.lock")&.config&.dig(:target_mode) || "random"
  end

  def leverage_photo_lock_photo_id
    item_for("leverage_photo.lock")&.config&.dig(:photo_id)
  end

  def leverage_photo_delete_enabled
    enabled?("leverage_photo.delete")
  end

  def leverage_photo_delete_target_mode
    item_for("leverage_photo.delete")&.config&.dig(:target_mode) || "random"
  end

  def leverage_photo_delete_photo_id
    item_for("leverage_photo.delete")&.config&.dig(:photo_id)
  end

  def chaster_add_time_active?
    item_for("chaster.add_time")&.active? || false
  end

  def chaster_freeze_active?
    item_for("chaster.freeze")&.active? || false
  end

  def pishock_active?
    item_for("pishock.shock")&.active? || false
  end

  def leverage_photo_lock_active?
    item_for("leverage_photo.lock")&.active? || false
  end

  def leverage_photo_delete_active?
    item_for("leverage_photo.delete")&.active? || false
  end
end
