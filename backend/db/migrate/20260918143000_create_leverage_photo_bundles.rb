# frozen_string_literal: true

class CreateLeveragePhotoBundles < ActiveRecord::Migration[7.2]
  def up
    create_table :leverage_photo_bundles do |t|
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_reference :leverage_photos, :bundle, foreign_key: { to_table: :leverage_photo_bundles }
    add_column :leverage_photos, :position, :integer, null: false, default: 0

    select_all("SELECT id, user_id, created_at, updated_at FROM leverage_photos").each do |row|
      bundle_id = insert(<<~SQL.squish)
        INSERT INTO leverage_photo_bundles (user_id, created_at, updated_at)
        VALUES (
          #{row["user_id"].to_i},
          #{connection.quote(row["created_at"])},
          #{connection.quote(row["updated_at"])}
        )
      SQL
      update(<<~SQL.squish)
        UPDATE leverage_photos
        SET bundle_id = #{bundle_id.to_i}, position = 0
        WHERE id = #{row["id"].to_i}
      SQL
    end

    change_column_null :leverage_photos, :bundle_id, false
    add_index :leverage_photos, [:bundle_id, :position]
  end

  def down
    remove_index :leverage_photos, [:bundle_id, :position]
    remove_reference :leverage_photos, :bundle, foreign_key: { to_table: :leverage_photo_bundles }
    remove_column :leverage_photos, :position
    drop_table :leverage_photo_bundles
  end
end
