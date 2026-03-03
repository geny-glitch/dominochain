class RemoveDislikesCountFromInfluencerImages < ActiveRecord::Migration[7.2]
  def change
    remove_column :influencer_images, :dislikes_count, :integer
  end
end
