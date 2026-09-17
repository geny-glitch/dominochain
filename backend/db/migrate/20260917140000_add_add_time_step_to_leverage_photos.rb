# frozen_string_literal: true

class AddAddTimeStepToLeveragePhotos < ActiveRecord::Migration[7.2]
  def change
    add_column :leverage_photos, :add_time_base_seconds, :integer
    add_column :leverage_photos, :add_time_step_n, :integer, default: 0, null: false
  end
end
