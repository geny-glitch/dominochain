# frozen_string_literal: true

class CreateLeveragePhotos < ActiveRecord::Migration[7.2]
  def change
    create_table :leverage_photos do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "draft"
      t.datetime :locked_until
      t.jsonb :drand_rounds, null: false, default: []
      t.string :drand_chain_hash
      t.integer :tlock_layer_count, null: false, default: 0
      t.integer :initial_duration_seconds

      t.timestamps
    end

    add_index :leverage_photos, :status
    add_index :leverage_photos, :locked_until

    create_table :leverage_photo_extensions do |t|
      t.references :leverage_photo, null: false, foreign_key: true
      t.integer :added_seconds, null: false
      t.datetime :locked_until_before, null: false
      t.datetime :locked_until_after, null: false
      t.bigint :drand_round_added, null: false

      t.timestamps
    end
  end
end
