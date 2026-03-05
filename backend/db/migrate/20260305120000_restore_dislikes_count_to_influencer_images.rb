# frozen_string_literal: true

class RestoreDislikesCountToInfluencerImages < ActiveRecord::Migration[7.2]
  def up
    return if column_exists?(:influencer_images, :dislikes_count)

    add_column :influencer_images, :dislikes_count, :integer, default: 0, null: false
  end

  def down
    remove_column :influencer_images, :dislikes_count, :integer if column_exists?(:influencer_images, :dislikes_count)
  end
end
