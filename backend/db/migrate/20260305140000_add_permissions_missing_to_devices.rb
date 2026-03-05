# frozen_string_literal: true

class AddPermissionsMissingToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :permissions_missing, :string
  end
end
