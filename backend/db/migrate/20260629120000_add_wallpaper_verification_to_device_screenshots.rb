# frozen_string_literal: true

class AddWallpaperVerificationToDeviceScreenshots < ActiveRecord::Migration[7.2]
  def change
    change_table :device_screenshots, bulk: true do |t|
      t.references :wallpaper, foreign_key: true, null: true
      t.float :similarity_score
      t.string :verification_status, default: "pending", null: false
      t.datetime :verified_at
    end

    add_index :device_screenshots, :verification_status
  end
end
