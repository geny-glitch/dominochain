# frozen_string_literal: true

# Aggregates user counts and active consequence pair totals for the admin stats dashboard.
class AdminStatsQuery
  ConsequenceCount = Struct.new(:source, :possibility_id, :count, keyword_init: true)

  Result = Struct.new(
    :total_users,
    :users_active_today,
    :consequence_counts,
    keyword_init: true
  )

  SHOWCASE_GAME_FIELDS = {
    showcase_quiz_enabled: :showcase_quiz_seconds_per_point,
    showcase_snake_enabled: :showcase_snake_seconds_per_fruit,
    showcase_dino_enabled: :showcase_dino_seconds_per_obstacle,
    showcase_tetris_enabled: :showcase_tetris_seconds_per_line
  }.freeze

  def self.call(reference_time: Time.current)
    new(reference_time: reference_time).call
  end

  def initialize(reference_time: Time.current)
    @reference_time = reference_time
    @today_range = reference_time.in_time_zone.all_day
  end

  def call
    Result.new(
      total_users: User.count,
      users_active_today: users_active_today_count,
      consequence_counts: aggregate_consequence_counts
    )
  end

  private

  attr_reader :reference_time, :today_range

  def users_active_today_count
    User.joins(:devices)
      .where(devices: { last_seen_at: today_range })
      .distinct
      .count
  end

  def aggregate_consequence_counts
    tallies = Hash.new(0)

    beta_users_scope.find_each do |user|
      pairs_for_user(user).each do |source, possibility_id|
        tallies[[source, possibility_id]] += 1
      end
    end

    tallies.map do |(source, possibility_id), count|
      ConsequenceCount.new(source: source, possibility_id: possibility_id, count: count)
    end.sort_by { |row| [-row.count, row.source, row.possibility_id] }
  end

  def beta_users_scope
    User.beta.includes(
      :wallpaper_enforcement_config,
      :cornertime_config,
      :strava_config,
      :strava_goals
    )
  end

  def pairs_for_user(user)
    pairs = []

    pairs.concat(scenario_pairs(user.wallpaper_enforcement_config, source: "wallpaper", active: wallpaper_active?(user)))
    pairs.concat(scenario_pairs(user.cornertime_config, source: "cornertime"))
    pairs.concat(strava_pairs(user))
    pairs.concat(fixed_source_pairs(user))

    pairs
  end

  def wallpaper_active?(user)
    config = user.wallpaper_enforcement_config
    config&.enabled?
  end

  def scenario_pairs(config, source:, active: true)
    return [] unless active
    return [] unless config

    config.scenario_set.scenarios.flat_map do |scenario|
      allowed = BetaEvents::ScenarioRegistry.allowed_actions_for(source.to_sym)
      scenario.to_sanction_set(allowed: allowed).active_items.map do |item|
        [source, item.possibility_id]
      end
    end
  end

  def strava_pairs(user)
    pairs = scenario_pairs(user.strava_config, source: "strava")

    user.strava_goals.select(&:enabled?).each do |goal|
      legacy = ScenarioSet.from_hash(goal.scenarios, source: :strava)
      legacy = ScenarioSet.from_legacy_strava_goal(goal) if legacy.empty?
      legacy.scenarios.each do |scenario|
        allowed = BetaEvents::ScenarioRegistry.allowed_actions_for(:strava)
        scenario.to_sanction_set(allowed: allowed).active_items.each do |item|
          pairs << ["strava", item.possibility_id]
        end
      end
    end

    pairs
  end

  def fixed_source_pairs(user)
    pairs = []

    if user.puryfi_seconds_per_label.values.any? { |seconds| seconds.to_i.positive? }
      pairs << ["puryfi", "chaster.add_time"]
    end

    if PuryfiConfig::LABEL_IDS.any? { |label_id| PuryfiConfig.shock_level_for_label(user, label_id).positive? }
      pairs << ["puryfi", "pishock.shock"]
    end

    if user.showcase_snake_seconds_per_fruit.to_i.positive?
      pairs << ["cigarettes", "chaster.add_time"]
    end

    SHOWCASE_GAME_FIELDS.each do |enabled_field, seconds_field|
      next unless user.public_send(enabled_field)
      next unless user.public_send(seconds_field).to_i.positive?

      pairs << ["showcase", "chaster.add_time"]
      pairs << ["showcase", "pishock.shock"]
    end

    if user.showcase_backdoor_enabled?
      pairs << ["showcase", "chaster.add_time"]
    end

    pairs
  end
end
