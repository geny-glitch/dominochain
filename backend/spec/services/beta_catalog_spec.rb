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
    expect(ids).not_to include("leverage_photo")
  end

  it "includes leverage_photo in action items when flag enabled" do
    stub_beta_catalog_feature_flags(
      "beta_source_wallpaper" => true,
      "beta_action_leverage_photo" => true
    )
    catalog = described_class.new(user)
    ids = catalog.action_items.map { |item| item[:id] }
    expect(ids).to include("leverage_photo")
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

  it "exposes sources_enabled_map and actions_enabled_map" do
    stub_beta_catalog_feature_flags(
      "beta_source_wallpaper" => true,
      "beta_source_cigarettes" => false,
      "beta_action_chaster" => true
    )
    user.update!(
      beta_ui_prefs: user.beta_ui_prefs.deep_merge(
        "catalog_visibility" => {
          "sources" => { "wallpaper" => true, "cigarettes" => true },
          "actions" => { "chaster" => true }
        }
      )
    )
    catalog = described_class.new(user)
    sources = catalog.sources_enabled_map
    actions = catalog.actions_enabled_map
    expect(sources["wallpaper"]).to eq(true)
    expect(sources["cigarettes"]).to eq(false)
    expect(actions["chaster"]).to eq(true)
  end
end
