class AddDislikesCountToInfluencerImages < ActiveRecord::Migration[7.2]
  def change
    add_column :influencer_images, :dislikes_count, :integer
  end
end
