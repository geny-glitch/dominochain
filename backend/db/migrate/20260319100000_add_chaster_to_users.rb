# frozen_string_literal: true

class AddChasterToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :chaster_access_token, :string
    add_column :users, :chaster_refresh_token, :string
    add_column :users, :chaster_token_expires_at, :datetime
  end
end
