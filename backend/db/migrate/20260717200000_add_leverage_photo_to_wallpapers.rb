# frozen_string_literal: true

class AddLeveragePhotoToWallpapers < ActiveRecord::Migration[7.2]
  def change
    add_reference :wallpapers, :leverage_photo, null: true, foreign_key: true
  end
end
