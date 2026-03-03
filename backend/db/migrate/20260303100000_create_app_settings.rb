# frozen_string_literal: true

class CreateAppSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :app_settings do |t|
      t.text :influencer_names

      t.timestamps
    end
  end
end
