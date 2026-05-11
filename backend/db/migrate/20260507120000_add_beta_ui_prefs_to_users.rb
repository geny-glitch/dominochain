# frozen_string_literal: true

class AddBetaUiPrefsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :beta_ui_prefs, :jsonb, null: false, default: {}
  end
end
