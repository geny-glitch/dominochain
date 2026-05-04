# frozen_string_literal: true

class AddShowcaseTetrisToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :showcase_tetris_enabled, :boolean, default: true, null: false
    add_column :users, :showcase_tetris_seconds_per_line, :integer, default: 60, null: false
    add_column :users, :showcase_tetris_seconds_per_line_at, :datetime
  end
end
