# frozen_string_literal: true

class AddPermissionsOkToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :permissions_ok, :boolean
    add_column :devices, :permissions_checked_at, :datetime
  end
end
