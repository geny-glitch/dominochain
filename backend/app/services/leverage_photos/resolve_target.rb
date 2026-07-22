# frozen_string_literal: true

class LeveragePhotos::ResolveTarget
  class Error < StandardError; end

  ACTIONS = {
    lock: :eligible_for_lock?,
    start: :eligible_for_start?,
    add_time: :eligible_for_add_time?,
    delete: :eligible_for_sanction_delete?
  }.freeze

  def self.call(user:, action:, target_mode:, photo_id: nil)
    new(user: user, action: action, target_mode: target_mode, photo_id: photo_id).call
  end

  def initialize(user:, action:, target_mode:, photo_id: nil)
    @user = user
    @action = action.to_sym
    @target_mode = target_mode.to_s
    @photo_id = photo_id
  end

  def call
    raise Error, "unsupported action" unless ACTIONS.key?(@action)

    pool = eligible_pool
    return nil if pool.empty?

    case @target_mode
    when "specific"
      resolve_specific(pool)
    when "random"
      resolve_random(pool)
    else
      nil
    end
  end

  private

  def eligible_pool
    scope = @user.leverage_photos.not_deleted
    predicate = ACTIONS[@action]
    scope.select { |photo| photo.public_send(predicate) }
  end

  def resolve_specific(pool)
    id = @photo_id.to_i
    return nil if id <= 0

    pool.find { |photo| photo.id == id }
  end

  def resolve_random(pool)
    return pool.sample unless @action == :lock

    active = pool.select(&:can_add_time?)
    return active.sample if active.any?

    pool.sample
  end
end
