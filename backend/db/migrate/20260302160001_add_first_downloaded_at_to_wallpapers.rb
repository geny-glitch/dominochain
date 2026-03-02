# frozen_string_literal: true

class AddFirstDownloadedAtToWallpapers < ActiveRecord::Migration[7.2]
  def change
    add_column :wallpapers, :first_downloaded_at, :datetime
  end
end
