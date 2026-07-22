# frozen_string_literal: true

class BetaCatalog
  PREF_ROOT = "catalog_visibility"
  SOURCES_KEY = "sources"
  ACTIONS_KEY = "actions"
  CACHE_NAMESPACE_KEY = "beta_catalog:feature_flags:namespace:v1"
  FLAGS_CACHE_VERSION = 6
  FLAGS_CACHE_TTL = 1.minute
  SOURCE_FEATURE_FLAGS = {
    "puryfi" => "beta_source_puryfi",
    "cigarettes" => "beta_source_cigarettes",
    "strava" => "beta_source_strava",
    "showcase" => "beta_source_showcase",
    "wallpaper" => "beta_source_wallpaper",
    "cornertime" => "beta_source_cornertime",
    "chess" => "beta_source_chess"
  }.freeze
  ACTION_FEATURE_FLAGS = {
    "chaster" => "beta_action_chaster",
    "pishock" => "beta_action_pishock",
    "leverage_photo" => "beta_action_leverage_photo"
  }.freeze

  SOURCE_DEFS = [
    {
      id: "puryfi",
      path_helper: :beta_sources_puryfi_path,
      action_name: "sources_puryfi"
    },
    {
      id: "cigarettes",
      path_helper: :beta_sources_cigarettes_path,
      action_name: "sources_cigarettes"
    },
    {
      id: "strava",
      path_helper: :beta_sources_strava_path,
      action_name: "sources_strava"
    },
    {
      id: "showcase",
      path_helper: :beta_sources_showcase_path,
      action_name: "sources_showcase"
    },
    {
      id: "wallpaper",
      path_helper: :beta_sources_wallpaper_path,
      action_name: "sources_wallpaper"
    },
    {
      id: "cornertime",
      path_helper: :beta_sources_cornertime_path,
      action_name: "sources_cornertime"
    },
    {
      id: "chess",
      path_helper: :beta_sources_chess_path,
      action_name: "sources_chess"
    }
  ].freeze

  ACTION_DEFS = [
    {
      id: "chaster",
      path_helper: :beta_actions_chaster_path,
      action_name: "actions_chaster"
    },
    {
      id: "pishock",
      path_helper: :beta_actions_pishock_path,
      action_name: "actions_pishock"
    },
    {
      id: "leverage_photo",
      path_helper: :beta_actions_leverage_photo_path,
      action_name: "actions_leverage_photo"
    }
  ].freeze

  EVENT_SOURCE_TO_CATALOG_SOURCE_ID = {
    "showcase_game" => "showcase",
    "showcase_backdoor" => "showcase",
    "strava_goal" => "strava",
    "cigarette" => "cigarettes",
    "puryfi" => "puryfi",
    "wallpaper" => "wallpaper",
    "cornertime" => "cornertime",
    "chess_com_goal" => "chess"
  }.freeze

  ACTION_CLASS_TO_CATALOG_ACTION_ID = {
    "BetaEvents::Actions::ChasterAddTimeFromEvent" => "chaster",
    "BetaEvents::Actions::ChasterFreezeFromEvent" => "chaster",
    "BetaEvents::Actions::ChasterUnfreezeFromEvent" => "chaster",
    "BetaEvents::Actions::EnqueuePishockFromEvent" => "pishock",
    "BetaEvents::Actions::LeveragePhotoLockFromEvent" => "leverage_photo",
    "BetaEvents::Actions::LeveragePhotoDeleteFromEvent" => "leverage_photo"
  }.freeze

  def initialize(user)
    @user = user
  end

  def self.expected_feature_flags
    (SOURCE_FEATURE_FLAGS.values + ACTION_FEATURE_FLAGS.values).compact.uniq.sort
  end

  def self.invalidate_feature_flags_cache!
    current_namespace = feature_flags_cache_namespace
    Rails.cache.write(CACHE_NAMESPACE_KEY, current_namespace + 1)
  end

  def self.feature_flags_cache_namespace
    Rails.cache.fetch(CACHE_NAMESPACE_KEY) { 1 }
  end

  def source_items
    SOURCE_DEFS
      .select { |definition| item_available_by_feature_flag?(SOURCES_KEY, definition[:id]) }
      .map { |d| decorate_source(d) }
  end

  def action_items
    ACTION_DEFS
      .select { |definition| item_available_by_feature_flag?(ACTIONS_KEY, definition[:id]) }
      .map { |d| decorate_action(d) }
  end

  def visible_source_items
    source_items.select { |item| source_enabled?(item[:id]) }
  end

  def visible_action_items
    action_items.select { |item| action_enabled?(item[:id]) }
  end

  def source_platform_enabled?(item_id)
    item_available_by_feature_flag?(SOURCES_KEY, item_id)
  end

  def action_platform_enabled?(item_id)
    item_available_by_feature_flag?(ACTIONS_KEY, item_id)
  end

  def source_enabled?(item_id)
    source_platform_enabled?(item_id) && item_enabled?(SOURCES_KEY, item_id)
  end

  def action_enabled?(item_id)
    item_available_by_feature_flag?(ACTIONS_KEY, item_id) && item_enabled?(ACTIONS_KEY, item_id)
  end

  def source_enabled_for_event_source?(event_source)
    source_id = EVENT_SOURCE_TO_CATALOG_SOURCE_ID[event_source.to_s]
    return true if source_id.blank?

    source_enabled?(source_id)
  end

  def action_enabled_for_class?(action_class)
    action_id = BetaEvents::ActionRegistry.catalog_id_for_executor(action_class) ||
      ACTION_CLASS_TO_CATALOG_ACTION_ID[action_class.to_s]
    return true if action_id.blank?

    action_enabled?(action_id)
  end

  def update_item_visibility(kind:, item_id:, enabled:)
    key = kind_to_key(kind)
    return false unless key
    return false unless allowed_item_ids_for(key).include?(item_id.to_s)
    return false unless item_available_by_feature_flag?(key, item_id)

    prefs = (@user.beta_ui_prefs || {}).deep_dup
    prefs[PREF_ROOT] ||= {}
    prefs[PREF_ROOT][key] ||= {}
    prefs[PREF_ROOT][key][item_id.to_s] = CheckboxParamNormalizer.to_bool(enabled)
    @user.update!(beta_ui_prefs: prefs)
    true
  end

  def item_label(kind:, item_id:)
    key = kind_to_key(kind)
    return nil unless key
    return nil unless allowed_item_ids_for(key).include?(item_id.to_s)

    scope = key == SOURCES_KEY ? "sources" : "actions"
    I18n.t("beta.catalog.#{scope}.#{item_id}.label")
  end

  private

  def item_available_by_feature_flag?(kind_key, item_id)
    flag_key = feature_flag_key_for(kind_key, item_id)
    return true if flag_key.blank?

    feature_flags.fetch(flag_key, false)
  end

  def feature_flag_key_for(kind_key, item_id)
    item = item_id.to_s
    case kind_key
    when SOURCES_KEY then SOURCE_FEATURE_FLAGS[item]
    when ACTIONS_KEY then ACTION_FEATURE_FLAGS[item]
    end
  end

  def evaluate_feature_flags
    keys = self.class.expected_feature_flags
    return default_enabled_flags(keys) if @user.posthog_distinct_id.blank?

    Rails.cache.fetch(feature_flags_cache_key, expires_in: FLAGS_CACHE_TTL, race_condition_ttl: 10.seconds) do
      evaluate_feature_flags_from_posthog(keys)
    end
  rescue StandardError => e
    Rails.logger.warn("[BetaCatalog] feature flags fallback false: #{e.class}: #{e.message}")
    default_disabled_flags(self.class.expected_feature_flags)
  end

  def evaluate_feature_flags_from_posthog(keys)
    evaluations = PostHog.evaluate_flags(
      @user.posthog_distinct_id,
      person_properties: @user.posthog_properties,
      flag_keys: keys
    )

    keys.index_with { |key| evaluations.enabled?(key) }
  end

  def default_enabled_flags(keys)
    keys.index_with(true)
  end

  def default_disabled_flags(keys)
    keys.index_with(false)
  end

  def feature_flags
    @feature_flags ||= evaluate_feature_flags
  end

  def feature_flags_cache_key
    namespace = self.class.feature_flags_cache_namespace
    "beta_catalog:feature_flags:v#{FLAGS_CACHE_VERSION}:#{namespace}:#{BgEnv.posthog_value}:#{@user.posthog_distinct_id}"
  end

  def decorate_source(definition)
    id = definition[:id]
    definition.merge(
      label: I18n.t("beta.catalog.sources.#{id}.label"),
      subtitle: I18n.t("beta.catalog.sources.#{id}.subtitle"),
      events: I18n.t("beta.catalog.sources.#{id}.events")
    )
  end

  def decorate_action(definition)
    id = definition[:id]
    definition.merge(
      label: I18n.t("beta.catalog.actions.#{id}.label"),
      subtitle: I18n.t("beta.catalog.actions.#{id}.subtitle"),
      events: I18n.t("beta.catalog.actions.#{id}.events")
    )
  end

  def kind_to_key(kind)
    case kind.to_s
    when "source" then SOURCES_KEY
    when "action" then ACTIONS_KEY
    else nil
    end
  end

  def allowed_item_ids_for(key)
    catalog_defs_for(key).map { |item| item[:id] }
  end

  def catalog_defs_for(key)
    key == SOURCES_KEY ? SOURCE_DEFS : ACTION_DEFS
  end

  def item_enabled?(key, item_id)
    value = @user.beta_ui_prefs&.dig(PREF_ROOT, key, item_id.to_s)
    value.nil? ? true : ActiveModel::Type::Boolean.new.cast(value)
  end
end
