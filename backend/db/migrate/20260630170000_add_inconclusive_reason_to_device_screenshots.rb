# frozen_string_literal: true

class AddInconclusiveReasonToDeviceScreenshots < ActiveRecord::Migration[7.2]
  def change
    add_column :device_screenshots, :inconclusive_reason, :string
    add_index :device_screenshots, :inconclusive_reason
  end
end
