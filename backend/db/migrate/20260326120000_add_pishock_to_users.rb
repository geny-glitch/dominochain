# frozen_string_literal: true

class AddPishockToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :pishock_enabled, :boolean, default: false, null: false
    add_column :users, :pishock_username, :string
    add_column :users, :pishock_share_code, :string
    add_column :users, :pishock_api_key, :string
  end
end
