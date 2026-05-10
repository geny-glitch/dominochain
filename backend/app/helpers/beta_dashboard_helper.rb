# frozen_string_literal: true

module BetaDashboardHelper
  def beta_source_catalog_items
    beta_catalog.source_items
  end

  def beta_action_catalog_items
    beta_catalog.action_items
  end

  def beta_visible_sidebar_source_items
    beta_catalog.visible_source_items
  end

  def beta_visible_sidebar_action_items
    beta_catalog.visible_action_items
  end

  def beta_catalog_source_enabled?(item_id)
    beta_catalog.source_enabled?(item_id)
  end

  def beta_catalog_action_enabled?(item_id)
    beta_catalog.action_enabled?(item_id)
  end

  def beta_nav_link(text, path, active: false)
    classes = [ "ds-beta-nav-link" ]
    classes << "ds-beta-nav-link--active" if active
    link_to text, path, class: classes.join(" ")
  end

  def beta_subnav_link(text, path, active: false)
    classes = [ "ds-beta-nav-link", "ds-beta-nav-link--sub" ]
    classes << "ds-beta-nav-link--active" if active
    link_to text, path, class: classes.join(" ")
  end

  def beta_event_source_label(source)
    {
      "puryfi" => "Purify",
      "cigarettes" => "Cigarettes",
      "showcase_game" => "Vitrine",
      "showcase_backdoor" => "Backdoor",
      "strava_goal" => "Strava",
      "api" => "API"
    }[source.to_s] || source.to_s.humanize
  end

  def beta_signed_duration(seconds)
    sign = seconds.to_i.negative? ? "-" : "+"
    total = seconds.to_i.abs
    h = total / 3600
    m = (total % 3600) / 60
    s = total % 60
    if h.positive?
      "#{sign}#{h}h #{m}min"
    elsif m.positive?
      "#{sign}#{m}min #{s}s"
    else
      "#{sign}#{s}s"
    end
  end

  private

  def beta_catalog
    @beta_catalog ||= BetaCatalog.new(current_user)
  end
end
