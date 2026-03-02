# frozen_string_literal: true

class AddScreenDimensionsToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :screen_width, :integer
    add_column :devices, :screen_height, :integer
  end
end
