class AddShowcaseDinoEnabledToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :showcase_dino_enabled, :boolean, default: true, null: false
  end
end
