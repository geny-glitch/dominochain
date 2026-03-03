# frozen_string_literal: true

class AddNameToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :name, :string
  end
end
