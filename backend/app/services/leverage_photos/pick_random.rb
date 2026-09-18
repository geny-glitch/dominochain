# frozen_string_literal: true

class LeveragePhotos::PickRandom
  def self.lockable(user:, exclude_id: nil)
    new(user: user, exclude_id: exclude_id).lockable
  end

  def self.any(user:)
    new(user: user).any
  end

  def initialize(user:, exclude_id: nil)
    @user = user
    @exclude_id = exclude_id.present? ? exclude_id.to_i : nil
  end

  def lockable_pool
    @user.leverage_photos.not_deleted.select(&:eligible_for_lock?)
  end

  def lockable
    pool = lockable_pool
    if @exclude_id.present? && pool.size > 1
      pool = pool.reject { |photo| photo.id == @exclude_id }
    end
    pool.sample
  end

  def any
    @user.leverage_photos.not_deleted.order(Arel.sql("RANDOM()")).first
  end
end
