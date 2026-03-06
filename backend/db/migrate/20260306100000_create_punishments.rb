# frozen_string_literal: true

class CreatePunishments < ActiveRecord::Migration[7.2]
  def change
    create_table :punishments do |t|
      t.references :task, null: false, foreign_key: true
      t.text :message

      t.timestamps
    end

    add_index :punishments, [:task_id, :created_at]
  end
end
