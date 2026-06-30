class AddPublicBossEnabledToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :public_boss_enabled, :boolean, default: false, null: false
  end
end
