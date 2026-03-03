# frozen_string_literal: true

class AddDeletedAtToTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :tasks, :deleted_at, :datetime
    add_index :tasks, :deleted_at
  end
end
