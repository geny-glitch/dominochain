# frozen_string_literal: true

class AddLikesAndHiddenToInfluencerImages < ActiveRecord::Migration[7.2]
  def change
    add_column :influencer_images, :likes_count, :integer, null: false, default: 0
    add_column :influencer_images, :hidden, :boolean, null: false, default: false
    add_index :influencer_images, :hidden
  end
end
