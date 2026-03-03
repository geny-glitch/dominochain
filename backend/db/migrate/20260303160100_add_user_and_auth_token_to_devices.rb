# frozen_string_literal: true

class AddUserAndAuthTokenToDevices < ActiveRecord::Migration[7.2]
  def change
    add_reference :devices, :user, foreign_key: true
    add_column :devices, :auth_token, :string
    add_index :devices, :auth_token, unique: true
  end
end
