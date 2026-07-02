# frozen_string_literal: true

class AddWallpaperVerificationAlgorithmToAppSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :app_settings, :wallpaper_verification_algorithm, :string,
               default: "local_match", null: false
  end
end
