# frozen_string_literal: true

module ZapProgramHelpers
  def enable_pishock_catalog!(user)
    prefs = (user.beta_ui_prefs || {}).deep_dup
    prefs["catalog_visibility"] ||= {}
    prefs["catalog_visibility"]["actions"] ||= {}
    prefs["catalog_visibility"]["actions"]["pishock"] = true
    user.update!(
      pishock_enabled: true,
      beta_ui_prefs: prefs
    )
  end
end

RSpec.configure do |config|
  config.include ZapProgramHelpers
end
