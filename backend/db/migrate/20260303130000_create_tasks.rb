# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[7.2]
  def change
    create_table :tasks do |t|
      t.references :device, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :expected_proof
      t.datetime :deadline_at, null: false
      t.boolean :trigger_alarm, default: false, null: false
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :tasks, [:device_id, :status]
  end
end
