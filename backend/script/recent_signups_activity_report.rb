# frozen_string_literal: true

# Summarizes recent user signups and their in-app activity.
#
# Run on production:
#   fly ssh console --pty -C "/rails/bin/rails runner script/recent_signups_activity_report.rb"
#
# Environment:
#   DAYS       — look back this many days from now (default: 30)
#   SINCE      — ISO8601 datetime override (e.g. 2026-06-01T00:00:00Z)
#   ROLE       — filter by role: beta, boss, admin (default: all non-admin)
#   USER_ID    — report a single user by id
#   NICKNAME   — report a single user by nickname
#   VERBOSE    — set to "1" to print recent chaster events and game sessions
#   JSON       — set to "1" for machine-readable output

require "json"

def parse_since
  if ENV["SINCE"].present?
    Time.zone.parse(ENV["SINCE"]) || abort("Invalid SINCE: #{ENV['SINCE']}")
  else
    ENV.fetch("DAYS", "30").to_i.days.ago
  end
end

def parse_role_scope
  return User.all if ENV["USER_ID"].present? || ENV["NICKNAME"].present?

  case ENV.fetch("ROLE", "non_admin").downcase
  when "all" then User.all
  when "beta" then User.beta
  when "boss" then User.boss
  when "admin" then User.admin
  else User.where.not(role: User.roles[:admin])
  end
end

def format_time(value)
  return "—" if value.blank?

  value.in_time_zone.strftime("%Y-%m-%d %H:%M %Z")
end

def format_ago(value)
  return "—" if value.blank?

  distance = time_ago_in_words(value)
  "#{format_time(value)} (#{distance} ago)"
end

def time_ago_in_words(from_time, to_time = Time.current)
  seconds = (to_time - from_time).to_i.abs
  case seconds
  when 0..59 then "#{seconds}s"
  when 60..3599 then "#{seconds / 60}m"
  when 3600..86_399 then "#{seconds / 3600}h"
  else "#{seconds / 86_400}d"
  end
end

def yes_no(value)
  value ? "yes" : "no"
end

def screenshot_stats_for(device_ids)
  return { count: 0, last_at: nil, by_status: {} } if device_ids.empty?

  scope = DeviceScreenshot.where(device_id: device_ids)
  {
    count: scope.count,
    last_at: scope.maximum(:captured_at),
    by_status: scope.group(:verification_status).count
  }
end

def last_activity_at(*timestamps)
  timestamps.compact.max
end

def build_user_report(user)
  devices = user.devices.order(Arel.sql("last_seen_at DESC NULLS LAST"), updated_at: :desc)
  device_ids = devices.pluck(:id)

  chaster_events = user.chaster_time_events
  game_sessions = user.game_sessions
  cigarette_entries = user.cigarette_entries
  tasks = user.tasks
  strava_goals = user.strava_goals
  strava_checks = user.strava_goal_checks
  compliance_checks = user.wallpaper_compliance_checks
  chaster_locks = user.chaster_locks.order(updated_at: :desc)
  screenshot_stats = screenshot_stats_for(device_ids)

  last_seen = devices.maximum(:last_seen_at)
  last_chaster_event = chaster_events.maximum(:occurred_at)
  last_game = game_sessions.maximum(:played_at)
  last_cigarette = cigarette_entries.maximum(:smoked_at)
  last_task = tasks.maximum(:created_at)
  last_compliance = compliance_checks.maximum(:checked_at)
  last_strava_check = strava_checks.maximum(:checked_at)

  last_activity = last_activity_at(
    last_seen,
    last_chaster_event,
    last_game,
    screenshot_stats[:last_at],
    last_compliance,
    last_cigarette,
    last_task,
    last_strava_check
  )

  control = user.control
  control_requests_sent = user.control_requests_sent
  control_requests_received = user.control_requests_received
  wallpaper_config = user.wallpaper_enforcement_config

  {
    id: user.id,
    nickname: user.nickname,
    email: user.email,
    role: user.role,
    uuid: user.uuid,
    signed_up_at: user.created_at,
    signed_up_ago: time_ago_in_words(user.created_at),
    integrations: {
      chaster: user.chaster_access_token.present?,
      strava: user.strava_access_token.present?,
      pishock: user.pishock_enabled?,
      puryfi: user.puryfi_plugin_token.present?,
      wallpaper_enforcement: wallpaper_config&.enabled == true
    },
    social: {
      controlled_by_boss: user.controlled_by_boss?,
      control_status: control&.status,
      boss_nickname: control&.boss&.nickname,
      control_requests_sent: control_requests_sent.group(:status).count,
      control_requests_received: control_requests_received.group(:status).count
    },
    devices: devices.map do |device|
      {
        id: device.id,
        name: device.display_name,
        screen: [device.screen_width, device.screen_height].compact.join("x").presence,
        last_seen_at: device.last_seen_at,
        permissions_ok: device.permissions_ok,
        permissions_missing: device.permissions_missing_list
      }
    end,
    counts: {
      devices: devices.size,
      chaster_locks: chaster_locks.size,
      chaster_time_events: chaster_events.count,
      game_sessions: game_sessions.count,
      screenshots: screenshot_stats[:count],
      wallpaper_compliance_checks: compliance_checks.count,
      cigarette_entries: cigarette_entries.count,
      tasks: tasks.count,
      strava_goals: strava_goals.count,
      strava_goal_checks: strava_checks.count
    },
    breakdowns: {
      chaster_time_events_by_source: chaster_events.group(:source).count,
      game_sessions_by_type: game_sessions.group(:game_type).count,
      screenshots_by_status: screenshot_stats[:by_status],
      chaster_locks_by_status: chaster_locks.group(:status).count
    },
    last_activity_at: last_activity,
    last_timestamps: {
      device_seen: last_seen,
      chaster_event: last_chaster_event,
      game_session: last_game,
      screenshot: screenshot_stats[:last_at],
      wallpaper_compliance: last_compliance,
      cigarette: last_cigarette,
      task: last_task,
      strava_check: last_strava_check
    },
    recent: {
      chaster_time_events: chaster_events.recent.limit(5).map do |event|
        {
          occurred_at: event.occurred_at,
          source: event.source,
          seconds: event.seconds,
          chaster_lock_id: event.chaster_lock_id
        }
      end,
      game_sessions: game_sessions.order(played_at: :desc).limit(5).map do |session|
        {
          played_at: session.played_at,
          game_type: session.game_type,
          score: session.score,
          player_name: session.player_name
        }
      end,
      chaster_locks: chaster_locks.limit(3).map do |lock|
        {
          title: lock.title,
          status: lock.status,
          start_date: lock.start_date,
          end_date: lock.end_date,
          unlocked_at: lock.unlocked_at
        }
      end
    }
  }
end

def print_user_report(report, verbose:)
  puts "=" * 80
  puts "#{report[:nickname]} (#{report[:role]}) — id=#{report[:id]}"
  puts "  email: #{report[:email]}"
  puts "  uuid:  #{report[:uuid]}"
  puts "  signed up: #{format_ago(report[:signed_up_at])}"
  puts

  integrations = report[:integrations]
  puts "Integrations:"
  puts "  chaster=#{yes_no(integrations[:chaster])}  strava=#{yes_no(integrations[:strava])}  " \
       "pishock=#{yes_no(integrations[:pishock])}  puryfi=#{yes_no(integrations[:puryfi])}  " \
       "wallpaper_enforcement=#{yes_no(integrations[:wallpaper_enforcement])}"
  puts

  social = report[:social]
  puts "Social:"
  puts "  controlled_by_boss=#{yes_no(social[:controlled_by_boss])}"
  if social[:control_status].present?
    puts "  control: #{social[:control_status]} (boss=#{social[:boss_nickname] || '—'})"
  end
  puts "  control_requests_sent: #{social[:control_requests_sent].presence || 'none'}"
  puts "  control_requests_received: #{social[:control_requests_received].presence || 'none'}"
  puts

  puts "Devices (#{report[:counts][:devices]}):"
  if report[:devices].empty?
    puts "  none"
  else
    report[:devices].each do |device|
      perms = device[:permissions_ok].nil? ? "unknown" : (device[:permissions_ok] ? "ok" : "missing")
      missing = device[:permissions_missing].presence
      line = "  - #{device[:name]} (#{device[:screen] || 'unknown size'}) " \
             "last_seen=#{format_ago(device[:last_seen_at])} permissions=#{perms}"
      line += " missing=#{missing.join(', ')}" if missing
      puts line
    end
  end
  puts

  counts = report[:counts]
  puts "Activity counts:"
  puts "  chaster_locks=#{counts[:chaster_locks]}  chaster_events=#{counts[:chaster_time_events]}  " \
       "games=#{counts[:game_sessions]}  screenshots=#{counts[:screenshots]}"
  puts "  wallpaper_checks=#{counts[:wallpaper_compliance_checks]}  cigarettes=#{counts[:cigarette_entries]}  " \
       "tasks=#{counts[:tasks]}  strava_goals=#{counts[:strava_goals]}/checks=#{counts[:strava_goal_checks]}"
  puts

  breakdowns = report[:breakdowns]
  if breakdowns.values.any?(&:present?)
    puts "Breakdowns:"
    puts "  chaster events by source: #{breakdowns[:chaster_time_events_by_source].presence || 'none'}"
    puts "  games by type: #{breakdowns[:game_sessions_by_type].presence || 'none'}"
    puts "  screenshots by status: #{breakdowns[:screenshots_by_status].presence || 'none'}"
    puts "  chaster locks by status: #{breakdowns[:chaster_locks_by_status].presence || 'none'}"
    puts
  end

  timestamps = report[:last_timestamps]
  puts "Last activity: #{format_ago(report[:last_activity_at])}"
  puts "  device seen: #{format_ago(timestamps[:device_seen])}"
  puts "  chaster event: #{format_ago(timestamps[:chaster_event])}"
  puts "  game session: #{format_ago(timestamps[:game_session])}"
  puts "  screenshot: #{format_ago(timestamps[:screenshot])}"
  puts "  wallpaper check: #{format_ago(timestamps[:wallpaper_compliance])}"
  puts "  cigarette: #{format_ago(timestamps[:cigarette])}"
  puts "  task: #{format_ago(timestamps[:task])}"
  puts "  strava check: #{format_ago(timestamps[:strava_check])}"

  return unless verbose

  puts
  puts "Recent chaster locks:"
  report[:recent][:chaster_locks].each do |lock|
    puts "  - #{lock[:title] || 'untitled'} status=#{lock[:status]} " \
         "end=#{format_time(lock[:end_date])} unlocked=#{format_time(lock[:unlocked_at])}"
  end

  puts
  puts "Recent chaster events:"
  report[:recent][:chaster_time_events].each do |event|
    sign = event[:seconds].positive? ? "+" : ""
    puts "  - #{format_time(event[:occurred_at])} #{event[:source]} #{sign}#{event[:seconds]}s"
  end

  puts
  puts "Recent game sessions:"
  report[:recent][:game_sessions].each do |session|
    puts "  - #{format_time(session[:played_at])} #{session[:game_type]} score=#{session[:score]} " \
         "player=#{session[:player_name] || '—'}"
  end
end

since = parse_since
scope = parse_role_scope

if ENV["USER_ID"].present?
  user = scope.find_by(id: ENV["USER_ID"]) || abort("User not found: id=#{ENV['USER_ID']}")
  users = User.where(id: user.id)
elsif ENV["NICKNAME"].present?
  user = scope.find_by(nickname: ENV["NICKNAME"]) || abort("User not found: nickname=#{ENV['NICKNAME']}")
  users = User.where(id: user.id)
else
  users = scope.where(created_at: since..).order(created_at: :desc)
end

verbose = ENV["VERBOSE"] == "1"
json_output = ENV["JSON"] == "1"

reports = users.map { |user| build_user_report(user) }

if json_output
  puts JSON.pretty_generate(
    {
      generated_at: Time.current.iso8601,
      since: since.iso8601,
      user_count: reports.size,
      users: reports
    }
  )
  exit 0
end

puts "Recent signups activity report"
puts "Since: #{format_time(since)}"
puts "Users: #{reports.size}"
puts

if reports.empty?
  puts "No users found."
  exit 0
end

reports.each { |report| print_user_report(report, verbose: verbose) }

puts "=" * 80
puts "Summary"
active_last_7d = reports.count do |report|
  report[:last_activity_at].present? && report[:last_activity_at] >= 7.days.ago
end
with_device = reports.count { |report| report[:counts][:devices].positive? }
with_chaster = reports.count { |report| report[:integrations][:chaster] }
with_any_events = reports.count { |report| report[:counts][:chaster_time_events].positive? }

puts "  total users: #{reports.size}"
puts "  with device: #{with_device}"
puts "  chaster connected: #{with_chaster}"
puts "  with chaster events: #{with_any_events}"
puts "  active in last 7 days: #{active_last_7d}"
