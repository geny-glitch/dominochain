class CreateWallpapers < ActiveRecord::Migration[7.2]
  def change
    create_table :wallpapers do |t|
      t.references :device, null: false, foreign_key: true

      t.timestamps
    end
  end
end
