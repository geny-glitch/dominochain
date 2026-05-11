# frozen_string_literal: true

# Which dashboard / API "capabilities" exist for a beta and which UI blocks are visible.
# Visibility: all sections shown by default; `user.beta_ui_prefs["hidden_sections"]` hides blocks by id.
class BetaCapabilities
  SECTION_IDS = %w[chaster strava puryfi pishock showcase control tasks devices].freeze

  def self.for(user)
    new(user)
  end

  def initialize(user)
    @user = user
  end

  def visible?(section_id)
    sid = section_id.to_s
    return false unless SECTION_IDS.include?(sid)

    hidden.exclude?(sid)
  end

  # For JSON API (Android / plugins): map section id -> visible
  def as_json
    SECTION_IDS.index_with { |s| visible?(s) }
  end

  def hidden
    Array(@user.beta_ui_prefs&.dig("hidden_sections")).map(&:to_s) & SECTION_IDS
  end
end
