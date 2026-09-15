# frozen_string_literal: true

class AddPublicPishockEnabledToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :public_pishock_enabled, :boolean, default: false, null: false
  end
end
