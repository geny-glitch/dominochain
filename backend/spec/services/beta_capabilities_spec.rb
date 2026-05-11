# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaCapabilities do
  let(:user) { create(:user, :beta) }

  it "shows all sections by default" do
    caps = described_class.for(user)
    described_class::SECTION_IDS.each do |sid|
      expect(caps.visible?(sid)).to be true
    end
  end

  it "hides sections listed in beta_ui_prefs" do
    user.update!(beta_ui_prefs: { "hidden_sections" => %w[pishock strava] })
    caps = described_class.for(user)
    expect(caps.visible?(:pishock)).to be false
    expect(caps.visible?(:strava)).to be false
    expect(caps.visible?(:chaster)).to be true
  end
end
