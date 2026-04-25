# frozen_string_literal: true

class AddShowcaseSnakeSecondsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :showcase_snake_seconds_per_fruit, :integer, default: 300, null: false
    add_column :users, :showcase_snake_seconds_per_fruit_at, :datetime
  end
end
