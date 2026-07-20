class User < ApplicationRecord
  SHOWCASE_SECONDS_DECREASE_COOLDOWN = 24.hours

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable,
         authentication_keys: [:email]

  enum role: { beta: 0, boss: 1, admin: 2 }

  has_many :devices, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_one :control, foreign_key: :beta_id, dependent: :destroy
  has_many :controls, foreign_key: :boss_id, dependent: :destroy
  has_many :control_requests_sent, class_name: "ControlRequest", foreign_key: :beta_id, dependent: :destroy
  has_many :control_requests_received, class_name: "ControlRequest", foreign_key: :boss_id, dependent: :destroy
  has_many :chaster_locks, dependent: :destroy
  has_many :chaster_time_events, dependent: :destroy
  has_many :game_sessions, dependent: :destroy
  has_many :showcase_add_time_events, dependent: :destroy
  has_many :showcase_time_additions, dependent: :destroy
  has_many :cigarette_entries, dependent: :destroy
  has_many :strava_goals, dependent: :destroy
  has_many :strava_goal_checks, dependent: :destroy
  has_one :strava_config, dependent: :destroy
  has_one :wallpaper_enforcement_config, dependent: :destroy
  has_many :wallpaper_verification_sessions, dependent: :destroy
  has_many :wallpaper_compliance_checks, dependent: :destroy
  has_one :cornertime_config, dependent: :destroy
  has_many :cornertime_sessions, dependent: :destroy
  has_many :leverage_photos, dependent: :destroy

  validates :nickname, presence: true, uniqueness: true
  validates :nickname, format: { with: /\A[a-zA-Z0-9_]+\z/, message: :invalid_nickname_format }
  validates :pishock_intensity_factor,
    numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :showcase_quiz_seconds_per_point,
    :showcase_snake_seconds_per_fruit,
    :showcase_dino_seconds_per_obstacle,
    :showcase_tetris_seconds_per_line,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 86_400 * 365 },
    if: :beta?
  validate :at_least_one_showcase_game_enabled, if: :validate_showcase_game_guard?
  validate :showcase_quiz_seconds_decrease_cooldown, if: :beta?
  validate :showcase_snake_seconds_decrease_cooldown, if: :beta?
  validate :showcase_dino_seconds_decrease_cooldown, if: :beta?
  validate :showcase_tetris_seconds_decrease_cooldown, if: :beta?
  validates :puryfi_min_score,
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 },
    if: :beta?

  before_validation :normalize_email
  before_validation :assign_nickname_from_email, on: :create
  before_validation :ensure_uuid, on: :create
  before_save :touch_showcase_quiz_seconds_changed_at, if: :will_save_change_to_showcase_quiz_seconds_per_point?
  before_save :touch_showcase_snake_seconds_changed_at, if: :will_save_change_to_showcase_snake_seconds_per_fruit?
  before_save :touch_showcase_dino_seconds_changed_at, if: :will_save_change_to_showcase_dino_seconds_per_obstacle?
  before_save :touch_showcase_tetris_seconds_changed_at, if: :will_save_change_to_showcase_tetris_seconds_per_line?
  before_validation :apply_beta_defaults, on: :create

  def self.generate_unique_nickname_from_email(email, excluding_id: nil)
    base = email.to_s.split("@", 2).first.to_s.downcase.gsub(/[^a-z0-9_]/, "_")
    base = "user" if base.blank?
    base = base[0, 24].sub(/_+\z/, "")
    base = "user" if base.blank?

    candidate = base
    suffix = 2
    scope = where(nickname: candidate)
    scope = scope.where.not(id: excluding_id) if excluding_id.present?

    while scope.exists?
      candidate = "#{base}_#{suffix}"
      suffix += 1
      scope = where(nickname: candidate)
      scope = scope.where.not(id: excluding_id) if excluding_id.present?
    end

    candidate
  end

  # Called by posthog-rails for automatic user association in error reports.
  def posthog_distinct_id
    self[:uuid]
  end

  def posthog_properties
    { email: email, role: role, nickname: nickname, date_joined: created_at&.iso8601 }
  end

  def puryfi_ws_url
    return nil if puryfi_plugin_token.blank?

    base = ENV.fetch("PURYFI_WS_PUBLIC_BASE", "wss://puryfi.dominochain.app").to_s.sub(%r{/+\z}, "")
    "#{base}/ws/#{puryfi_plugin_token}"
  end

  def ensure_puryfi_plugin_token!
    return if puryfi_plugin_token.present?

    update_column(:puryfi_plugin_token, SecureRandom.hex(32))
  end

  def regenerate_puryfi_plugin_token!
    update_column(:puryfi_plugin_token, SecureRandom.hex(32))
  end

  def ensure_wallpaper_enforcement_config!
    wallpaper_enforcement_config || create_wallpaper_enforcement_config!
  end

  def ensure_cornertime_config!
    cornertime_config || create_cornertime_config!
  end

  def ensure_strava_config!
    strava_config || create_strava_config!
  end

  def controlled_by_boss?
    control&.accepted?
  end

  def primary_device
    devices.order(Arel.sql("last_seen_at DESC NULLS LAST"), updated_at: :desc).first
  end

  def active_wallpaper_verification_session
    wallpaper_verification_sessions.active.first
  end

  def wallpaper_verification_session_locked?
    active_wallpaper_verification_session.present?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end

  def assign_nickname_from_email
    return if nickname.present? || email.blank?

    self.nickname = self.class.generate_unique_nickname_from_email(email)
  end

  def ensure_uuid
    self[:uuid] ||= SecureRandom.uuid
  end

  def apply_beta_defaults
    return unless beta?

    self.showcase_quiz_enabled = false
    self.showcase_snake_enabled = false
    self.showcase_dino_enabled = false
    self.showcase_tetris_enabled = false
    self.showcase_backdoor_enabled = false
    self.public_boss_enabled = false

    prefs = (beta_ui_prefs || {}).deep_dup
    prefs["catalog_visibility"] ||= {}
    prefs["catalog_visibility"]["sources"] = {
      "puryfi" => false,
      "cigarettes" => false,
      "strava" => false,
      "showcase" => false,
      "wallpaper" => false
    }
    prefs["catalog_visibility"]["actions"] = {
      "chaster" => false,
      "pishock" => false,
      "leverage_photo" => false
    }
    self.beta_ui_prefs = prefs
  end

  def validate_showcase_game_guard?
    return false unless beta?
    return false if new_record?

    will_save_change_to_showcase_quiz_enabled? ||
      will_save_change_to_showcase_snake_enabled? ||
      will_save_change_to_showcase_dino_enabled? ||
      will_save_change_to_showcase_tetris_enabled? ||
      will_save_change_to_showcase_backdoor_enabled?
  end

  def at_least_one_showcase_game_enabled
    return if showcase_quiz_enabled || showcase_snake_enabled || showcase_dino_enabled || showcase_tetris_enabled || showcase_backdoor_enabled

    errors.add(:base, I18n.t("activerecord.errors.models.user.at_least_one_showcase_game"))
  end

  def showcase_quiz_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_quiz_seconds_per_point,
      showcase_quiz_seconds_per_point_was,
      showcase_quiz_seconds_per_point,
      showcase_quiz_seconds_per_point_at_in_database
    )
  end

  def showcase_snake_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_snake_seconds_per_fruit,
      showcase_snake_seconds_per_fruit_was,
      showcase_snake_seconds_per_fruit,
      showcase_snake_seconds_per_fruit_at_in_database
    )
  end

  def showcase_dino_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_dino_seconds_per_obstacle,
      showcase_dino_seconds_per_obstacle_was,
      showcase_dino_seconds_per_obstacle,
      showcase_dino_seconds_per_obstacle_at_in_database
    )
  end

  def showcase_tetris_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_tetris_seconds_per_line,
      showcase_tetris_seconds_per_line_was,
      showcase_tetris_seconds_per_line,
      showcase_tetris_seconds_per_line_at_in_database
    )
  end

  def touch_showcase_quiz_seconds_changed_at
    self.showcase_quiz_seconds_per_point_at = Time.current
  end

  def touch_showcase_snake_seconds_changed_at
    self.showcase_snake_seconds_per_fruit_at = Time.current
  end

  def touch_showcase_dino_seconds_changed_at
    self.showcase_dino_seconds_per_obstacle_at = Time.current
  end

  def touch_showcase_tetris_seconds_changed_at
    self.showcase_tetris_seconds_per_line_at = Time.current
  end

  def enforce_showcase_seconds_decrease_cooldown(attribute, previous_value, current_value, last_changed_at)
    return unless public_send("#{attribute}_changed?")
    return if previous_value.nil?
    return if current_value >= previous_value
    return if last_changed_at.blank?

    return if Time.current >= last_changed_at + SHOWCASE_SECONDS_DECREASE_COOLDOWN

    unlock_at = last_changed_at + SHOWCASE_SECONDS_DECREASE_COOLDOWN
    errors.add(
      attribute,
      I18n.t(
        "activerecord.errors.models.user.showcase_seconds_decrease_cooldown",
        unlock_at: I18n.l(unlock_at, format: :unlock)
      )
    )
  end
end
