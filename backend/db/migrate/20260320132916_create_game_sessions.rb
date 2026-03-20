class CreateGameSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :game_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :game_type, null: false, default: "snake"
      t.datetime :played_at, null: false
      t.integer :score, null: false, default: 0
      t.string :player_name

      t.timestamps
    end

    add_index :game_sessions, [:user_id, :game_type]
  end
end
