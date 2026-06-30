# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaCatalog do
  let(:user) { create(:user, :beta) }

  before do
    stub_beta_catalog_feature_flags("beta_source_wallpaper" => true)
  end

  it "includes wallpaper in source items" do
    catalog = described_class.new(user)
    ids = catalog.source_items.map { |item| item[:id] }
    expect(ids).to include("wallpaper")
  end

  it "maps wallpaper events to the wallpaper catalog source" do
    user.update!(
      beta_ui_prefs: user.beta_ui_prefs.deep_merge(
        "catalog_visibility" => { "sources" => { "wallpaper" => true } }
      )
    )
    catalog = described_class.new(user)
    expect(catalog.source_enabled_for_event_source?(:wallpaper)).to eq(true)
  end
end
