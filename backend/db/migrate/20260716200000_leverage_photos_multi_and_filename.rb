# frozen_string_literal: true

class LeveragePhotosMultiAndFilename < ActiveRecord::Migration[7.2]
  def change
    remove_index :leverage_photos, :user_id
    add_index :leverage_photos, :user_id

    add_column :leverage_photos, :original_filename, :string
  end
end
