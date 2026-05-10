# frozen_string_literal: true

class BetaCatalog
  PREF_ROOT = "catalog_visibility"
  SOURCES_KEY = "sources"
  ACTIONS_KEY = "actions"

  SOURCE_ITEMS = [
    {
      id: "puryfi",
      label: "Purify (PuryFi)",
      subtitle: "Extension navigateur · détections par étiquette",
      events: "Événement: detection.label",
      path_helper: :beta_sources_puryfi_path,
      action_name: "sources_puryfi"
    },
    {
      id: "cigarettes",
      label: "Cigarettes",
      subtitle: "App Android · déclarations manuelles",
      events: "Événement: cigarette.created",
      path_helper: :beta_sources_cigarettes_path,
      action_name: "sources_cigarettes"
    },
    {
      id: "strava",
      label: "Strava",
      subtitle: "Objectifs glissants (1, 7 ou X jours)",
      events: "Événement: goal.failed",
      path_helper: :beta_sources_strava_path,
      action_name: "sources_strava"
    },
    {
      id: "showcase",
      label: "Vitrine",
      subtitle: "Page publique, QR, jeux, backdoor",
      events: "Événements: Snake, Quiz, Tétris, Dino, backdoor",
      path_helper: :beta_sources_showcase_path,
      action_name: "sources_showcase"
    }
  ].freeze

  ACTION_ITEMS = [
    {
      id: "chaster",
      label: "Chaster",
      subtitle: "Lock principal · temps restant",
      events: "Consomme le temps envoyé par les sources",
      path_helper: :beta_actions_chaster_path,
      action_name: "actions_chaster"
    },
    {
      id: "pishock",
      label: "PiShock",
      subtitle: "Collier / shocker · réactions physiques",
      events: "Actions: zap, intensité multipliée par facteur Z",
      path_helper: :beta_actions_pishock_path,
      action_name: "actions_pishock"
    }
  ].freeze

  EVENT_SOURCE_TO_CATALOG_SOURCE_ID = {
    "showcase_game" => "showcase",
    "showcase_backdoor" => "showcase",
    "strava_goal" => "strava",
    "cigarette" => "cigarettes",
    "api_chaster" => "puryfi"
  }.freeze

  ACTION_CLASS_TO_CATALOG_ACTION_ID = {
    "BetaEvents::Actions::ChasterAddTimeFromEvent" => "chaster",
    "BetaEvents::Actions::RecordShowcaseLimiterFromEvent" => "chaster",
    "BetaEvents::Actions::EnqueuePishockForShowcaseGame" => "pishock"
  }.freeze

  def initialize(user)
    @user = user
  end

  def source_items
    SOURCE_ITEMS
  end

  def action_items
    ACTION_ITEMS
  end

  def visible_source_items
    SOURCE_ITEMS.select { |item| source_enabled?(item[:id]) }
  end

  def visible_action_items
    ACTION_ITEMS.select { |item| action_enabled?(item[:id]) }
  end

  def source_enabled?(item_id)
    item_enabled?(SOURCES_KEY, item_id)
  end

  def action_enabled?(item_id)
    item_enabled?(ACTIONS_KEY, item_id)
  end

  def source_enabled_for_event_source?(event_source)
    source_id = EVENT_SOURCE_TO_CATALOG_SOURCE_ID[event_source.to_s]
    return true if source_id.blank?

    source_enabled?(source_id)
  end

  def action_enabled_for_class?(action_class)
    action_id = ACTION_CLASS_TO_CATALOG_ACTION_ID[action_class.to_s]
    return true if action_id.blank?

    action_enabled?(action_id)
  end

  def update_item_visibility(kind:, item_id:, enabled:)
    key = kind_to_key(kind)
    return false unless key
    return false unless allowed_item_ids_for(key).include?(item_id.to_s)

    prefs = (@user.beta_ui_prefs || {}).deep_dup
    prefs[PREF_ROOT] ||= {}
    prefs[PREF_ROOT][key] ||= {}
    prefs[PREF_ROOT][key][item_id.to_s] = ActiveModel::Type::Boolean.new.cast(enabled)
    @user.update!(beta_ui_prefs: prefs)
    true
  end

  def item_label(kind:, item_id:)
    key = kind_to_key(kind)
    return nil unless key

    catalog_items_for(key).find { |item| item[:id] == item_id.to_s }&.fetch(:label, nil)
  end

  private

  def kind_to_key(kind)
    case kind.to_s
    when "source" then SOURCES_KEY
    when "action" then ACTIONS_KEY
    else nil
    end
  end

  def allowed_item_ids_for(key)
    catalog_items_for(key).map { |item| item[:id] }
  end

  def catalog_items_for(key)
    key == SOURCES_KEY ? SOURCE_ITEMS : ACTION_ITEMS
  end

  def item_enabled?(key, item_id)
    value = @user.beta_ui_prefs&.dig(PREF_ROOT, key, item_id.to_s)
    value.nil? ? true : ActiveModel::Type::Boolean.new.cast(value)
  end
end
