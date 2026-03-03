# frozen_string_literal: true

class CreateDeviceScreenshots < ActiveRecord::Migration[7.2]
  def change
    create_table :device_screenshots do |t|
      t.references :device, null: false, foreign_key: true
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :device_screenshots, [:device_id, :captured_at]
  end
end
