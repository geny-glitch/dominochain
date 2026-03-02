class CreateDevices < ActiveRecord::Migration[7.2]
  def change
    create_table :devices do |t|
      t.string :device_id
      t.string :fcm_token

      t.timestamps
    end
    add_index :devices, :device_id, unique: true
  end
end
