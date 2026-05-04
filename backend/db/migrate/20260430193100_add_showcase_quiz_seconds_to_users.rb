class AddShowcaseQuizSecondsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :showcase_quiz_seconds_per_point, :integer, default: 1, null: false
    add_column :users, :showcase_quiz_seconds_per_point_at, :datetime
  end
end
