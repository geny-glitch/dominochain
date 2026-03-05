# frozen_string_literal: true

class EnsureAppSettingsInfluencerNames < ActiveRecord::Migration[7.2]
  def up
    unless table_exists?(:app_settings)
      create_table :app_settings do |t|
        t.text :influencer_names
        t.timestamps
      end
      return
    end

    unless column_exists?(:app_settings, :influencer_names)
      add_column :app_settings, :influencer_names, :text
    end
  end

  def down
    # Irreversible - we don't want to drop app_settings if it was created here
  end
end
