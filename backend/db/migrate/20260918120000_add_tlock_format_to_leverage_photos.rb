# frozen_string_literal: true

class AddTlockFormatToLeveragePhotos < ActiveRecord::Migration[7.2]
  def change
    add_column :leverage_photos, :tlock_format, :string, null: false, default: "full_image"
  end
end
