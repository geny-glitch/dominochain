class AddShowcaseDinoSecondsToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :showcase_dino_seconds_per_obstacle, :integer, default: 300, null: false
    add_column :users, :showcase_dino_seconds_per_obstacle_at, :datetime
    execute <<~SQL.squish
      UPDATE users
      SET showcase_dino_seconds_per_obstacle = showcase_snake_seconds_per_fruit,
          showcase_dino_seconds_per_obstacle_at = showcase_snake_seconds_per_fruit_at
      WHERE showcase_snake_seconds_per_fruit IS NOT NULL
    SQL
  end

  def down
    remove_column :users, :showcase_dino_seconds_per_obstacle_at
    remove_column :users, :showcase_dino_seconds_per_obstacle
  end
end
