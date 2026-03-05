# frozen_string_literal: true

class TasksBelongToUser < ActiveRecord::Migration[7.2]
  def up
    add_column :tasks, :user_id, :bigint
    add_foreign_key :tasks, :users, column: :user_id

    # Migrate existing tasks: set user_id from device
    execute <<-SQL.squish
      UPDATE tasks SET user_id = devices.user_id
      FROM devices WHERE tasks.device_id = devices.id AND devices.user_id IS NOT NULL
    SQL

    # Remove proof_of_completions for orphaned tasks first (FK constraint)
    execute <<-SQL.squish
      DELETE FROM proof_of_completions
      WHERE task_id IN (SELECT id FROM tasks WHERE user_id IS NULL)
    SQL

    # Remove orphaned tasks (device deleted or device has no user)
    execute "DELETE FROM tasks WHERE user_id IS NULL"

    change_column_null :tasks, :user_id, false

    remove_foreign_key :tasks, :devices
    remove_index :tasks, [:device_id, :status] if index_exists?(:tasks, [:device_id, :status])
    remove_index :tasks, :device_id if index_exists?(:tasks, :device_id)
    remove_column :tasks, :device_id

    add_index :tasks, [:user_id, :status]
  end

  def down
    add_column :tasks, :device_id, :bigint

    # Reverse migrate: pick first device of user for each task
    execute <<-SQL.squish
      UPDATE tasks SET device_id = (
        SELECT id FROM devices WHERE devices.user_id = tasks.user_id LIMIT 1
      )
    SQL

    # Remove tasks whose user has no devices
    execute "DELETE FROM tasks WHERE device_id IS NULL"
    change_column_null :tasks, :device_id, false
    add_foreign_key :tasks, :devices, column: :device_id
    add_index :tasks, [:device_id, :status]
    add_index :tasks, :device_id

    remove_foreign_key :tasks, :users
    remove_index :tasks, [:user_id, :status] if index_exists?(:tasks, [:user_id, :status])
    remove_column :tasks, :user_id
  end
end
