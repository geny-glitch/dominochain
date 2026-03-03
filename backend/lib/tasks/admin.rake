# frozen_string_literal: true

namespace :admin do
  desc "Promote a user to admin role (usage: rake admin:promote[admin] or NICKNAME=admin rake admin:promote)"
  task :promote, [:nickname] => :environment do |_t, args|
    nickname = args[:nickname].presence || ENV["NICKNAME"]
    abort "Usage: rake admin:promote[admin] or NICKNAME=admin rake admin:promote" if nickname.blank?

    user = User.find_by(nickname: nickname)
    abort "User '#{nickname}' not found." unless user

    user.update!(role: :admin)
    puts "User #{nickname} is now admin."
  end

  desc "Demote an admin to regular user (usage: rake admin:demote[admin] or NICKNAME=admin rake admin:demote)"
  task :demote, [:nickname] => :environment do |_t, args|
    nickname = args[:nickname].presence || ENV["NICKNAME"]
    abort "Usage: rake admin:demote[admin] or NICKNAME=admin rake admin:demote" if nickname.blank?

    user = User.find_by(nickname: nickname)
    abort "User '#{nickname}' not found." unless user

    user.update!(role: :beta)
    puts "User #{nickname} is no longer admin."
  end
end
