# frozen_string_literal: true

class CreateControls < ActiveRecord::Migration[7.2]
  def change
    create_table :controls do |t|
      t.references :boss, null: false, foreign_key: { to_table: :users }
      t.references :beta, null: false, foreign_key: { to_table: :users }, index: { unique: true }
      t.integer :status, default: 0, null: false

      t.timestamps
    end
  end
end
