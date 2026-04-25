# frozen_string_literal: true

class AddShowcaseGameFlagsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :showcase_quiz_enabled, :boolean, default: true, null: false
    add_column :users, :showcase_snake_enabled, :boolean, default: true, null: false
  end
end
