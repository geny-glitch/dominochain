# frozen_string_literal: true

class ReplaceBackdoorTokenWithEnabledFlag < ActiveRecord::Migration[7.2]
  def up
    unless column_exists?(:users, :backdoor_enabled)
      add_column :users, :backdoor_enabled, :boolean, null: false, default: false
    end

    return unless column_exists?(:users, :backdoor_token_digest)

    execute <<-SQL.squish
      UPDATE users SET backdoor_enabled = true WHERE backdoor_token_digest IS NOT NULL
    SQL
    remove_index :users, name: "index_users_on_backdoor_token_digest"
    remove_column :users, :backdoor_token_digest
  end

  def down
    remove_column :users, :backdoor_enabled if column_exists?(:users, :backdoor_enabled)
    return if column_exists?(:users, :backdoor_token_digest)

    add_column :users, :backdoor_token_digest, :string
    add_index :users, :backdoor_token_digest, unique: true, where: "backdoor_token_digest IS NOT NULL"
  end
end
