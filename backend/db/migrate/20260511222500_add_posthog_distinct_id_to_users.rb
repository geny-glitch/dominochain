# frozen_string_literal: true

class AddPosthogDistinctIdToUsers < ActiveRecord::Migration[7.2]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    add_column :users, :uuid, :string unless column_exists?(:users, :uuid)

    say_with_time "Backfilling uuid for existing users" do
      MigrationUser.where(uuid: [ nil, "" ]).find_each do |user|
        user.update_columns(uuid: SecureRandom.uuid, updated_at: Time.current)
      end
    end

    change_column_null :users, :uuid, false
    add_index :users, :uuid, unique: true unless index_exists?(:users, :uuid, unique: true)
  end

  def down
    remove_index :users, :uuid if index_exists?(:users, :uuid)
    remove_column :users, :uuid if column_exists?(:users, :uuid)
  end
end
