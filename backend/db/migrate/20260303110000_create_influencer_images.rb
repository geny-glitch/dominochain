# frozen_string_literal: true

class CreateInfluencerImages < ActiveRecord::Migration[7.2]
  def change
    create_table :influencer_images do |t|
      t.string :url, null: false
      t.string :name, null: false
      t.string :source, null: false, default: "wikimedia"

      t.timestamps
    end

    add_index :influencer_images, :url, unique: true
    add_index :influencer_images, :name
  end
end
