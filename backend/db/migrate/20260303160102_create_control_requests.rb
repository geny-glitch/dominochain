# frozen_string_literal: true

class CreateControlRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :control_requests do |t|
      t.references :beta, null: false, foreign_key: { to_table: :users }
      t.references :boss, null: false, foreign_key: { to_table: :users }
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :control_requests, [:beta_id, :boss_id], unique: true
  end
end
