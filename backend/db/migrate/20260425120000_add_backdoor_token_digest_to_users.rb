# frozen_string_literal: true

class AddBackdoorTokenDigestToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :backdoor_token_digest, :string
    add_index :users, :backdoor_token_digest, unique: true, where: "backdoor_token_digest IS NOT NULL"

    create_table :showcase_add_time_events do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :seconds, null: false
      t.timestamps
    end
    add_index :showcase_add_time_events, [:user_id, :created_at]
  end
end
