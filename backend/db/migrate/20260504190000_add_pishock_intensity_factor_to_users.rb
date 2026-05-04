# frozen_string_literal: true

class AddPishockIntensityFactorToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :pishock_intensity_factor, :decimal, precision: 5, scale: 2, default: 1.0, null: false
  end
end
