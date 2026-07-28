# frozen_string_literal: true

# Fold singular censored_image + teaser_image into has_many :censored_images.
class MigrateLeveragePhotoCensoredVersions < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      UPDATE active_storage_attachments
      SET name = 'censored_images'
      WHERE record_type = 'LeveragePhoto'
        AND name IN ('censored_image', 'teaser_image')
    SQL
  end

  def down
    # Best-effort reverse: first attachment per record → censored_image, rest → teaser_image.
    say_with_time "splitting censored_images back to censored_image/teaser_image" do
      rows = select_all(<<~SQL.squish)
        SELECT id, record_id
        FROM active_storage_attachments
        WHERE record_type = 'LeveragePhoto'
          AND name = 'censored_images'
        ORDER BY record_id ASC, id ASC
      SQL

      seen = {}
      rows.each do |row|
        record_id = row["record_id"].to_i
        name = if seen[record_id]
          "teaser_image"
        else
          seen[record_id] = true
          "censored_image"
        end
        execute "UPDATE active_storage_attachments SET name = #{quote(name)} WHERE id = #{row['id'].to_i}"
      end
    end
  end
end
