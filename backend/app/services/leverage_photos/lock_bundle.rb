# frozen_string_literal: true

class LeveragePhotos::LockBundle
  class Error < StandardError; end

  def self.start!(photo:, duration_seconds:)
    new(photo: photo).start!(duration_seconds: duration_seconds)
  end

  def self.add_time!(photo:, added_seconds:, save_as_base: false, apply_next_step: false)
    new(photo: photo).add_time!(
      added_seconds: added_seconds,
      save_as_base: save_as_base,
      apply_next_step: apply_next_step
    )
  end

  def initialize(photo:)
    @photo = photo
  end

  def start!(duration_seconds:)
    members = @photo.bundle_lock_targets
    raise Error, "photo cannot be locked" if members.empty?
    raise Error, "photo cannot be locked" unless members.all?(&:can_start_timer?)

    duration_seconds = duration_seconds.to_i
    locked_until = Time.current + duration_seconds.seconds
    last = nil
    members.each do |member|
      last = LeveragePhotos::StartTimerServer.new(
        photo: member,
        duration_seconds: duration_seconds,
        locked_until: locked_until
      ).call!
    end
    last
  rescue LeveragePhotos::StartTimerServer::Error => e
    raise Error, e.message
  end

  def add_time!(added_seconds:, save_as_base: false, apply_next_step: false)
    members = @photo.bundle_lock_targets
    raise Error, "cannot add time" if members.empty?
    raise Error, "cannot add time" unless members.all?(&:can_add_time?)

    added_seconds = added_seconds.to_i
    raise Error, "invalid added_seconds" if added_seconds <= 0

    base = members.map(&:locked_until).compact.max || Time.current
    locked_until = [base, Time.current].max + added_seconds.seconds
    last = nil
    members.each do |member|
      last = LeveragePhotos::AddTimeServer.new(
        photo: member,
        added_seconds: added_seconds,
        save_as_base: save_as_base,
        apply_next_step: apply_next_step,
        locked_until: locked_until
      ).call!
    end
    last
  rescue LeveragePhotos::AddTimeServer::Error => e
    raise Error, e.message
  end
end
