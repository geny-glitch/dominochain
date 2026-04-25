# frozen_string_literal: true

class DropRedundantBackdoorEnabled < ActiveRecord::Migration[7.2]
  def up
    return unless column_exists?(:users, :backdoor_enabled)

    execute <<-SQL.squish
      UPDATE users SET showcase_backdoor_enabled = true
      WHERE backdoor_enabled = true AND showcase_backdoor_enabled = false
    SQL
    remove_column :users, :backdoor_enabled
  end

  def down
    return if column_exists?(:users, :backdoor_enabled)

    add_column :users, :backdoor_enabled, :boolean, null: false, default: false
    execute <<-SQL.squish
      UPDATE users SET backdoor_enabled = true WHERE showcase_backdoor_enabled = true
    SQL
  end
end
