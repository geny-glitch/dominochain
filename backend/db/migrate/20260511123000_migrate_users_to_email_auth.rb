# frozen_string_literal: true

class MigrateUsersToEmailAuth < ActiveRecord::Migration[7.2]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    say_with_time "Backfilling user emails" do
      used_emails = {}

      MigrationUser.order(:id).find_each do |user|
        email = normalized_email(user.email)
        email = fallback_email(user) if email.blank?
        email = unique_email(email, used_emails, user.id)

        user.update_columns(email: email, updated_at: Time.current)
        used_emails[email] = true
      end
    end

    remove_index :users, :email if index_exists?(:users, :email)
    change_column_null :users, :email, false
    add_index :users, :email, unique: true unless index_exists?(:users, :email, unique: true)
  end

  def down
    remove_index :users, :email if index_exists?(:users, :email)
    change_column_null :users, :email, true
    add_index :users, :email unless index_exists?(:users, :email)
  end

  private

  def normalized_email(email)
    email.to_s.strip.downcase
  end

  def fallback_email(user)
    nickname = user.nickname.to_s.strip.downcase.gsub(/[^a-z0-9_]/, "_")
    nickname = "user#{user.id}" if nickname.blank?
    "#{nickname}@dominochain.app"
  end

  def unique_email(email, used_emails, user_id)
    return email unless used_emails[email] || MigrationUser.where(email: email).where.not(id: user_id).exists?

    local_part, domain = email.split("@", 2)
    domain = "dominochain.app" if domain.blank?

    counter = 1

    loop do
      suffix = counter == 1 ? "user#{user_id}" : "user#{user_id}_#{counter}"
      candidate = "#{local_part}+#{suffix}@#{domain}"
      return candidate unless used_emails[candidate] || MigrationUser.where(email: candidate).where.not(id: user_id).exists?

      counter += 1
    end
  end
end
