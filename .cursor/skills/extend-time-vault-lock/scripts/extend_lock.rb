# frozen_string_literal: true

# Rails runner payload for Time Vault locks on a Fly machine.
# Same dispatch as BetaEvents::Actions::LeveragePhotoLockFromEvent:
#   can_add_time?    -> AddTimeServer (wrap existing blob)
#   can_start_timer? -> StartTimerServer (first encrypt of original, or wrap after unlock)
# Do not run against a local DB unless that is the target.

require "json"

email = ENV.fetch("ADD_TIME_EMAIL")
duration = ENV.fetch("ADD_TIME_DURATION", "random")
count = Integer(ENV.fetch("ADD_TIME_COUNT", "1"))
ids = ENV.fetch("ADD_TIME_IDS", "").split(",").map(&:strip).reject(&:empty?).map(&:to_i)

UNIT_SECONDS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze
RANDOM_RANGE = (1.day.to_i..7.days.to_i)

def parse_seconds(spec)
  spec = spec.to_s.strip
  return :random if spec.empty? || spec.casecmp("random").zero?
  return spec.to_i if spec.match?(/\A\d+\z/)

  match = spec.match(/\A(\d+)([smhd])\z/i)
  raise "invalid duration #{spec.inspect}; use random, seconds, or 24h/7d/90m" unless match

  match[1].to_i * UNIT_SECONDS.fetch(match[2].downcase)
end

def seconds_for(duration_kind)
  seconds = duration_kind == :random ? rand(RANDOM_RANGE) : duration_kind
  raise "duration must be > 0" if seconds.to_i <= 0

  seconds
end

def apply_lock!(photo, seconds)
  if photo.can_add_time?
    LeveragePhotos::AddTimeServer.new(photo: photo, added_seconds: seconds).call!
    "add_time"
  elsif photo.can_start_timer?
    unless seconds.between?(LeveragePhoto::MIN_DURATION_SECONDS, LeveragePhoto::MAX_DURATION_SECONDS)
      raise "start_timer duration #{seconds}s is outside #{LeveragePhoto::MIN_DURATION_SECONDS}–#{LeveragePhoto::MAX_DURATION_SECONDS}"
    end

    LeveragePhotos::StartTimerServer.new(photo: photo, duration_seconds: seconds).call!
    "start_timer"
  else
    raise "photo #{photo.id} is not eligible for lock"
  end
end

user = User.find_by!(email: email)
add_time_pool = user.leverage_photos.select(&:can_add_time?)
start_pool = user.leverage_photos.select(&:can_start_timer?)
# Prefer already-locked photos, same as LeveragePhotos::ResolveTarget lock/random.
eligible = (add_time_pool + start_pool).uniq
raise "no eligible photos for #{email}" if eligible.empty?

photos =
  if ids.any?
    by_id = eligible.index_by(&:id)
    missing = ids - by_id.keys
    raise "ineligible or unknown photo ids for #{email}: #{missing.inspect}" if missing.any?

    ids.map { |id| by_id.fetch(id) }
  else
    raise "COUNT must be >= 1" if count < 1
    raise "only #{eligible.size} eligible photos, requested #{count}" if count > eligible.size

    (add_time_pool.shuffle + start_pool.shuffle).uniq.take(count)
  end

duration_kind = parse_seconds(duration)

results = photos.map do |photo|
  seconds = seconds_for(duration_kind)
  before_until = photo.locked_until
  before_status = photo.status
  action = apply_lock!(photo, seconds)
  photo.reload
  {
    id: photo.id,
    action: action,
    status_before: before_status,
    status_after: photo.status,
    added_seconds: seconds,
    added_hours: (seconds / 3600.0).round(2),
    locked_until_before: before_until,
    locked_until_after: photo.locked_until,
    tlock_layer_count: photo.tlock_layer_count
  }
end

puts JSON.pretty_generate(
  email: email,
  eligible_count: eligible.size,
  add_time_eligible: add_time_pool.size,
  start_timer_eligible: start_pool.size,
  results: results
)
