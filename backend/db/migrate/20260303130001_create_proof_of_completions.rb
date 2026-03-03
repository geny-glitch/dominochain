# frozen_string_literal: true

class CreateProofOfCompletions < ActiveRecord::Migration[7.2]
  def change
    create_table :proof_of_completions do |t|
      t.references :task, null: false, foreign_key: true
      t.text :text
      t.string :status, default: "pending", null: false
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :proof_of_completions, :status
  end
end
